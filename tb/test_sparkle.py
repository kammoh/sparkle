import random
from types import ModuleType
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Combine, FallingEdge, Join, Timer
from dataclasses import dataclass
from typing import Tuple, Union, Dict, List, Coroutine
import asyncio
from cffi import FFI
from pathlib import Path
import inspect
import sys
import os
import inspect
import importlib
import importlib.util
from .ValidReadyTester import ValidReadyTester, ValidReadyDesc

FRAME = inspect.currentframe()
assert FRAME
SCRIPT_DIR = os.path.realpath(os.path.dirname(
    inspect.getfile(FRAME)))

headers = dict(aead='''
int crypto_aead_encrypt(
    unsigned char *c, unsigned long long *clen,
    const unsigned char *m, unsigned long long mlen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *nsec,
    const unsigned char *npub,
    const unsigned char *k
);
int crypto_aead_test(
    unsigned char *c, unsigned long long *clen,
    const unsigned char *m, unsigned long long mlen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *nsec,
    const unsigned char *npub,
    const unsigned char *k
);
int crypto_aead_decrypt(
    unsigned char *m, unsigned long long *mlen,
    unsigned char *nsec,
    const unsigned char *c,unsigned long long clen,
    const unsigned char *ad,unsigned long long adlen,
    const unsigned char *npub,
    const unsigned char *k
);\n''', hash='int crypto_hash(unsigned char *out, const unsigned char *in, unsigned long long hlen);\n'
               )

DEBUG_LEVEL = 0
force_recompile = True
root_cref_dir = Path(SCRIPT_DIR).parent / 'cref'
algorithms = {'aead': 'schwaemm256128v2'}
cffi_build_dir = Path.cwd()


def build_libs():
    for op, algorithm in algorithms.items():
        if algorithm is None:
            continue
        header = headers[op]
        print(header)
        ffibuilder = FFI()
        cref_dir = root_cref_dir / f'crypto_{op}' / algorithm / 'ref'
        hdr_file = cref_dir / f"crypto_{op}.h"
        if not hdr_file.exists():
            with open(hdr_file, 'w') as f:
                f.write(header)
        api_h = cref_dir / f"api.h"
        if api_h.exists():
            with open(api_h) as f:
                header += '\n' + f.read()

        ffibuilder.cdef(header)
        define_macros = []
        if DEBUG_LEVEL:
            define_macros.append(('VERBOSE_LEVEL', DEBUG_LEVEL))
        ffibuilder.set_source(f"cffi_{algorithm}_{op}",
                              header,
                              libraries=[],
                              sources=[str(s)
                                       for s in cref_dir.glob("*.c")],
                              include_dirs=[cref_dir],
                              define_macros=define_macros
                              )
        ffibuilder.compile(tmpdir=cffi_build_dir,
                           verbose=1, target=None, debug=None)


if force_recompile:
    build_libs()

importlib.invalidate_caches()
sys.path.append(str(cffi_build_dir))


clib_modules = {}

for op, algorithm in algorithms.items():
    # from cffi_xoodyakv1_aead import ffi as aead_ffi, lib as aead_lib
    spec = importlib.util.find_spec(f'cffi_{algorithm}_{op}')
    if not spec:
        raise ModuleNotFoundError
    mod = spec.loader.load_module()
    assert mod
    clib_modules[(op, algorithm)] = mod


def encrypt(pt: bytes, ad: bytes, npub: bytes, key: bytes) -> Tuple[bytes, bytes]:
    """ returns tag, ct """
    aead_mod = clib_modules[('aead', 'schwaemm256128v2')]
    assert aead_mod
    lib = aead_mod.lib
    ffi = aead_mod.ffi
    assert len(key) == lib.CRYPTO_KEYBYTES
    assert len(npub) == lib.CRYPTO_NPUBBYTES
    ct = bytes(len(pt) + lib.CRYPTO_ABYTES)
    ct_len = ffi.new('unsigned long long*')

    ret = lib.crypto_aead_encrypt(ct, ct_len, pt, len(
        pt), ad, len(ad), ffi.NULL, npub, key)
    assert ret == 0
    assert ct_len[0] == len(ct)
    tag = ct[-lib.CRYPTO_ABYTES:]
    ct = ct[:-lib.CRYPTO_ABYTES]
    return ct, tag


def aead_test(pt: bytes, ad: bytes, npub: bytes, key: bytes) -> bytes:
    """ test """
    aead_mod = clib_modules[('aead', 'schwaemm256128v2')]
    assert aead_mod
    lib = aead_mod.lib
    ffi = aead_mod.ffi
    assert len(key) == lib.CRYPTO_KEYBYTES
    assert len(npub) == lib.CRYPTO_NPUBBYTES
    ct_len = ffi.new('unsigned long long*')
    ct = bytes(256 // 8)

    ret = lib.crypto_aead_test(ct, ct_len, pt, len(
        pt), ad, len(ad), ffi.NULL, npub, key)
    ct_len = ct_len[0]
    print(f'aead_test.ct_len: {ct_len}')
    assert ct_len <= len(ct)
    ct = ct[:ct_len]
    return ct


def rand_bytes(num_bytes: int) -> bytes:
    return bytes(random.getrandbits(8) for _ in range(num_bytes))


def bytes_to_words(x: bytes, width=32, byteorder='little') -> List[int]:
    assert width % 8 == 0
    word_bytes = width // 8
    remain = len(x) % word_bytes
    if remain:
        x += b'\0'*(word_bytes - remain)
    ret = [
        int.from_bytes(x[i:i + word_bytes], byteorder)
        for i in range(0, len(x), word_bytes)
    ]
    # print(f'bytes_to_words: {x.hex()} -> {[hex(r) for r in  ret]}')
    return ret


rand_inputs = False


def gen_inputs(numbytes):
    s = 0 if numbytes > 1 else 1
    return rand_bytes(numbytes) if rand_inputs else bytes([i % 255 for i in range(s, numbytes+s)])


def byte_seq(l: int, s: int = 0) -> bytes:
    return bytes([i % 255 for i in range(s, s+l)])


def to_bdi(b: bytes, ad: bool = False, ct: bool = False, hm: bool = False, eoi: bool = False):
    words = [{'word': w, 'ad': ad, 'ct': ct, 'hm': hm, 'valid_bytes': 0xf, 'last': False, 'eoi': False}
             for w in bytes_to_words(b)]
    if len(words) > 0:
        words[-1]['last'] = 1
        words[-1]['eoi'] = eoi
        m4 = len(b) % 4
        if m4 != 0:
            words[-1]['valid_bytes'] = (1 << m4) - 1
    return words


def to_bdo(b: bytes):
    words = [{'word': w, 'valid_bytes': 0xf, 'last': False}
             for w in bytes_to_words(b)]
    if len(words) > 0:
        words[-1]['last'] = 1
        m4 = len(b) % 4
        if m4 != 0:
            words[-1]['valid_bytes'] = (1 << m4) - 1
    return words


@cocotb.test()
async def test_perm(dut):
    """ Test sparkle permutation """
    tb = ValidReadyTester(
        dut,
        drivers=[
            ValidReadyDesc(name='key', data_fields=[None]),
            ValidReadyDesc(name='bdi', data_fields=[
                           'word', 'last', 'eoi', 'ad', 'ct', 'hm', 'valid_bytes'])
        ],
        monitors=[ValidReadyDesc(name='bdo', data_fields=[
                                 'word', 'last', 'valid_bytes'])]
    )

    await tb.start()

    dut.key_update.setimmediatevalue(0)

    for t in range(0, 1):
        # ad_bytes = 4
        # msg_bytes = 0

        decrypt = True

        key = rand_bytes(128//8)
        npub = byte_seq(256//8, 0x30)
        # npub = rand_bytes(256//8)

        # ad = byte_seq(ad_bytes, s=0x50)
        # msg = byte_seq(msg_bytes, s=0x70)
        # ad = rand_bytes(ad_bytes)
        # msg = rand_bytes(msg_bytes)

        key=bytes.fromhex('9E9C205F071B4EC734006D24F377C8BF')
        npub=bytes.fromhex('896E5772F43915B61B31CDC2C07AC9F77CAAD01ADFA65B75787720A1930EDE2A')
        ad=bytes.fromhex('E6')
        msg=bytes.fromhex('')

        ct, tag = encrypt(msg, ad, npub, key)

        print(f'ct: {ct.hex()}  tag: {tag.hex()}')

        # in_words = bytes_to_words(key + npub)

        npub_bdi = to_bdi(npub, eoi=len(ad) == 0 and len(msg) == 0)
        ad_bdi = to_bdi(ad, ad=True, eoi=len(msg) == 0)
        msg_bdi = to_bdi(ct if decrypt else msg, ct=decrypt, eoi=True)

        await tb.join(
            tb.drivers.key.enqueue_seq(bytes_to_words(key)),
            tb.drivers.bdi.enqueue_seq(npub_bdi + ad_bdi + msg_bdi),
            tb.monitors.bdo.expect_seq(
                to_bdo(msg if decrypt else ct) + to_bdo(tag))
        )
        print(f"test {t} done")
