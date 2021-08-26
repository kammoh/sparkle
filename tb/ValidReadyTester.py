from logging import Logger
from math import ceil
from types import SimpleNamespace
from typing import Coroutine, List, Optional, Sequence, Union, Dict, Callable
import random
from queue import Queue
import cocotb
from cocotb.binary import BinaryValue
from cocotb.clock import Clock
from cocotb.result import TestError, TestFailure
from cocotb.handle import ModifiableObject, HierarchyObject
from cocotb.triggers import Combine, FallingEdge, First, Join, ReadOnly, RisingEdge, Timer, with_timeout
from abc import ABC, abstractmethod
from enum import Enum, unique
from dataclasses import dataclass, field


def chunks(l, n):
    for i in range(0, len(l), n):
        yield l[i:i+n]


class Stalls(ABC):
    @abstractmethod
    def __call__(self) -> int:
        pass


class FixedStalls(Stalls):
    def __init__(self, num_stalls: int):
        self.num_stalls = num_stalls

    def __call__(self) -> int:
        return self.num_stalls


class NoStalls(FixedStalls):
    def __init__(self):
        super().__init__(0)


class RandStalls(Stalls):
    def __init__(self, max_stalls: int, min_stalls: int = 0):
        self.max_stalls = max_stalls
        self.min_stalls = min_stalls

    def get(self) -> int:
        return max(0, random.randint(self.min_stalls, self.max_stalls))


@dataclass
class BaseBusDesc:
    name: str
    data_fields: Union[List[Union[None, str]],
                       Dict[str, str]] = field(default_factory=[None])
    clock_sig_name: str = "clk"
    clock_edge: str = 'posedge'
    irrevocable: bool = False


@dataclass
class ValidReadyDesc(BaseBusDesc):
    valid_sig_name: Optional[str] = None
    ready_sig_name: Optional[str] = None

    def __post_init__(self):
        if not self.name:
            raise ValueError('name cannot be empty')
        # if not values.get('clock_sig_name'):
            # values['clock_sig_name'] = 'clock'
        if not self.valid_sig_name:
            self.valid_sig_name = f'{self.name}_valid'
        if not self.ready_sig_name:
            self.ready_sig_name = f'{self.name}_ready'
        if isinstance(self.data_fields, list):
            self.data_fields = {
                field: f'{self.name}_bits_{field}' if field else f'{self.name}_bits' for field in self.data_fields
            }


class VRBase:
    def __init__(self, dut: HierarchyObject, desc: ValidReadyDesc) -> None:
        self.dut = dut
        self.log: Logger = dut._log
        self.name: str = desc.name
        assert desc.valid_sig_name and desc.ready_sig_name
        self.data_fields = desc.data_fields
        assert isinstance(desc.data_fields, dict)
        self._data_sigs: Dict[str, ModifiableObject] = {
            f: getattr(dut, n) for f, n in desc.data_fields.items()
        }
        # TODO pending on https://github.com/cocotb/cocotb/pull/1128
        self._valid: ModifiableObject = getattr(dut, desc.valid_sig_name)
        assert len(self._valid) == 1, 'valid signal should be 1 bit'
        self._ready: ModifiableObject = getattr(dut, desc.ready_sig_name)
        assert len(self._ready) == 1, 'ready signal should be 1 bit'
        self.clock: ModifiableObject = getattr(dut, desc.clock_sig_name)
        assert len(self.clock) == 1, 'clock signal should be 1 bit'
        self.clock_edge = RisingEdge(
            self.clock) if desc.clock_edge == 'posedge' else FallingEdge(self.clock)


LiteralTerm = Union[int, str, bool, BinaryValue]
Literal = Union[LiteralTerm, Dict[str, LiteralTerm]]


class ValidReadyDriver(VRBase):
    def __init__(self, dut: HierarchyObject, desc: ValidReadyDesc, debug=False, stalls: Callable[[], int] = NoStalls()) -> None:
        super().__init__(dut, desc)
        self._debug = debug
        self.stalls = stalls
        # dut._id(f"{sig_name}", extended=False) ?
        self._data_sig_widths = {
            f: len(sig) for f, sig in self._data_sigs.items()
        }
        for f, sig in self._data_sigs.items():
            sig.setimmediatevalue(0)
        self._valid.setimmediatevalue(0)

    def poke_data(self, data: Literal) -> None:
        if isinstance(data, dict):
            for f, v in data.items():
                self._data_sigs[f].value = v
        else:
            assert len(self._data_sigs) == 1
            list(self._data_sigs.values())[0].value = data

    async def enqueue_seq(self, seq: Sequence[Literal]) -> None:
        for el in seq:
            r = self.stalls()
            if r > 0:
                self._valid.value = 0
                for _ in range(r):
                    await self.clock_edge
            self._valid.value = 1
            self.poke_data(el)
            await ReadOnly()
            while not self._ready.value:
                await self.clock_edge
                await ReadOnly()
            await self.clock_edge
        self._valid.value = 0


class ValidReadyMonitor(VRBase):
    def __init__(self, dut: HierarchyObject, desc: ValidReadyDesc, failure_limit=1, debug=False, stalls: Callable[[], int] = NoStalls()) -> None:
        super().__init__(dut, desc)

        self.failures = 0
        self.failure_limit = failure_limit
        self.num_received_words = 0
        self._debug = debug
        self.queue: Queue[List[int]] = Queue()
        self.stalls = stalls
        self._ready.setimmediatevalue(0)

    def peek_data(self) -> Dict[str, BinaryValue]:
        return {f: sig.value for f, sig in self._data_sigs.items()}

    # def compare_hex(el, received) -> bool:
        # exp = f'{el:0{self._data_width/4}x}'
        # try:
        #     received = f'{int(received):0{self._data_width/4}x}'
        # except:  # has Xs etc
        #     received = str(received)  # Note: binary string with Xs

    def compare_data(self, actual: Dict[str, BinaryValue], expected: Literal) -> bool:
        # TODO add support for don't cares (X/-) in the expected words (should be binary string then?)
        def els_match(actual_el: BinaryValue, exp_el: Literal):
            if actual_el.integer != exp_el:
                digits = len(actual_el) // 4  # TODO FIXME
                try:
                    actual_el = f'{int(actual_el):0{digits}x}'
                except:  # has Xs etc
                    actual_el = str(actual_el)  # Note: binary string with Xs
                self.log.error(
                    f"[monitor:{self.name}] received: {actual_el} expected: {exp_el:0{digits}x}")
                return False
            return True

        if isinstance(expected, dict):
            for f, exp in expected.items():
                received = actual[f]
                if not els_match(received, exp):
                    return False
        else:
            received = list(actual.values())[0]
            if not els_match(received, expected):
                return False
        return True

    async def expect_seq(self, seq: Sequence[Literal]) -> None:
        # await ReadOnly()
        for el in seq:
            # TODO add custom ready generator
            r = self.stalls()
            if r > 0:
                self._ready.value = 0
                for _ in range(r):
                    await self.clock_edge

            self._ready.value = 1
            await ReadOnly()
            while self._valid.value != 1:
                await self.clock_edge  # TODO optimize by wait for valid = 1 if valid was != 0 ?
                await ReadOnly()

            actual = self.peek_data()
            self.num_received_words += 1

            if not self.compare_data(actual, el):
                self.failures += 1
                if self.failures >= self.failure_limit:
                    await self.clock_edge
                    raise TestFailure(
                        f"{self.name} output did not match in {self.failures} words"
                    )
            await self.clock_edge

        self._ready.value = 0


class ValidReadyTester:
    def __init__(self, dut: HierarchyObject, drivers: List[ValidReadyDesc], monitors: List[ValidReadyDesc], clock_name='clk', reset_name='reset', reset_val=1, debug=False, clock_period=10, units='ns', in_stalls: Callable[[], int] = NoStalls(), out_stalls: Callable[[], int] = NoStalls()) -> None:
        self.dut = dut
        self.log = dut._log
        self.started = False
        self.reset = getattr(dut, reset_name)
        self.reset_val = reset_val
        self.clock = getattr(dut, clock_name)
        self.clock_period = clock_period
        self.units = units
        self.clock_edge = RisingEdge(self.clock)
        self.drivers = SimpleNamespace(
            **{desc.name: ValidReadyDriver(dut, desc, debug=debug, stalls=in_stalls) for desc in drivers}
        )
        self.monitors = SimpleNamespace(
            **{desc.name: ValidReadyMonitor(dut, desc, debug=debug, stalls=out_stalls) for desc in monitors}
        )

        self._forked_clock = None

    async def reset_dut(self, duration):
        self.reset <= self.reset_val
        await Timer(duration, units=self.units)
        self.reset <= (not self.reset_val)
        await self.clock_edge
        self.log.debug("Reset complete")

    async def start(self):
        if not self.started:
            clock = Clock(self.clock, period=self.clock_period,
                          units=self.units)
            self._forked_clock = cocotb.fork(clock.start())
            await cocotb.fork(self.reset_dut(2.5*self.clock_period))
            self.started = True

    async def join(self, *coro_list: Coroutine, timeout: Union[None, int, float] = None):
        aws = [cocotb.fork(c) for c in coro_list]
        comb = Combine(*aws)
        if timeout:
            await with_timeout(comb, timeout, self.units)
        else:
            await comb
