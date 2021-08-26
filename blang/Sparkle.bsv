package Sparkle;

//===================================================================================================================//
// Author          Kamyar Mohajerani (kamyar@ieee.org)
// Copyright       2021
// Description     Schwaemm and Esch: Lightweight Authenticated Encryption and Hashing using the Sparkle Permutation
// TODO            Hashing (Esch) not implemented yet
//===================================================================================================================//


import CryptoCore     :: *;
import BluelightUtils :: *;
import SIPO           :: *;
import PISO           :: *;

// Parameters:
typedef 256 RATE;
typedef 128 CAPACITY;
typedef 11 STEPS_BIG; // 10, 11, 12
typedef 7 STEPS_SLIM; // 8 for Sparkle512, o/w 7

typedef TDiv#(128, 32)        KEY_WORDS;
typedef TAdd#(RATE, CAPACITY) STATE_BITS;
typedef TDiv#(STATE_BITS, 64) STATE_BRANS;
typedef TDiv#(STATE_BITS, 32) STATE_WORDS;
typedef TDiv#(RATE, 32)       RATE_WORDS;
typedef 4 TAG_WORDS;

typedef Bit#(32) Word;
typedef Vector#(STATE_WORDS, Word) SparkleState;
typedef Vector#(RATE_WORDS, Word) RateBuffer;
typedef Vector#(RATE_WORDS, ValidBytes#(Word)) RateValidBytes;

Bit#(32) roundConst[8] = {
    'hB7E15162, 'hBF715880, 'h38B4DA56, 'h324E7738, 'hBB1185EB, 'h4F7C7B57, 'hCFBFA1C8, 'hC2B3293D
};

function Tuple2#(Word, Word) arxbox1(Word x, Word y, Word c, Bit#(r1) r1_,  Bit#(r2) r2_)
        provisos (Add#(r1, a1_, 32), Add#(r2, a2__, 32));
    x = x + rotateRight(y, r1_);
    return tuple2(x ^ c, y ^ rotateRight(x, r2_));
endfunction

function Tuple2#(Word,Word) alzette(Word x, Word y, Word c);
    let t = tuple2(x, y);
    t = arxbox1(tpl_1(t), tpl_2(t), c, 31'b0, 24'b0);
    t = arxbox1(tpl_1(t), tpl_2(t), c, 17'b0, 17'b0);
    t = arxbox1(tpl_1(t), tpl_2(t), c, 00'b0, 31'b0);
    t = arxbox1(tpl_1(t), tpl_2(t), c, 24'b0, 16'b0);
    return t;
endfunction

function Word ell(Word x );
    Tuple2#(Bit#(16), Bit#(16)) x_splitted = split(x);
    match {.hi, .lo} = x_splitted;
    return {lo, hi ^ lo};
endfunction

function SparkleState linear_layer(SparkleState state);
    Word tmpx = state[0], tmpy = state[1];
    let x0 = state[0], y0 = state[1], b = valueof(STATE_BRANS);
    for (Integer i = 1; i < b / 2; i = i + 1) begin
        tmpx = tmpx ^ state[i * 2];
        tmpy = tmpy ^ state[i * 2 + 1];
    end
    tmpx = ell(tmpx);
    tmpy = ell(tmpy);
    for (Integer i = 1; i < b / 2; i = i + 1) begin
        state[i * 2 - 2]     = state[i * 2 + b]     ^ state[i * 2]     ^ tmpy;
        state[i * 2 + b]     = state[i * 2];
        state[i * 2 - 1]     = state[i * 2 + b + 1] ^ state[i * 2 + 1] ^ tmpx;
        state[i * 2 + b + 1] = state[i * 2 + 1];
    end
    state[b - 2] = state[b]     ^ x0 ^ tmpy;
    state[b]     = x0;
    state[b - 1] = state[b + 1] ^ y0 ^ tmpx;
    state[b + 1] = y0;
    return state;
endfunction


function SparkleState sparkle_step(SparkleState t, StepCounter step);
    t[1] = t[1] ^ roundConst[step[2:0]];
    t[3][valueof(SizeOf#(StepCounter)) - 1:0] = truncate(t[3]) ^ step;
    for (Integer i = 0; i < valueof(STATE_BRANS); i = i + 1) begin
       let tp = alzette(t[2 * i], t[2 * i + 1], roundConst[i]);
       t[2*i]     = tpl_1(tp);
       t[2*i + 1] = tpl_2(tp);
    end
    t = linear_layer(t);
    return t;
endfunction

function w__ inbuf_word(w__ word1, w__ word2, Bit#(nbytes) valid_bytes, Bool ct)
        provisos (Bits#(w__, n), Mul#(nbytes, SizeOf#(Byte), n), Div#(n, SizeOf#(Byte), nbytes));
        
    Vector#(nbytes, Byte) w1 = toChunks(pack(word1));
    Vector#(nbytes, Byte) w2 = toChunks(pack(word2));
    for (Integer i = 0; i < valueof(nbytes); i = i + 1) begin
        if (ct && valid_bytes[i] == 0)
            w1[i] = w2[i];
    end
    return unpack(pack(w1));
endfunction

function Tuple2#(RateBuffer, SparkleState) rho_whiten(Bool ct, Bool ad, Bool lastBlock, Bool incomplete, RateBuffer inbuf, RateValidBytes valids, SparkleState state);
    if (lastBlock) begin
        Bit#(3) const_x = ad ? (incomplete ? 4 : 5) : (incomplete ? 6 : 7);
        state[valueof(STATE_WORDS) - 1][26 : 24] = Vector::last(state)[26 : 24] ^ const_x;
    end
    RateBuffer outbuf = xorVecs(inbuf, take(state));
    for (Integer i = 0; i < valueof(RATE_WORDS) / 2; i = i + 1) begin
        let j = i + valueof(RATE_WORDS) / 2;
        let wi = inbuf_word(inbuf[i], outbuf[i], valids[i], ct);
        let wj = inbuf_word(inbuf[j], outbuf[j], valids[j], ct);
        let z = state[j] ^ wi ^ state[valueof(RATE_WORDS) + i];
        let t = state[i] ^ wj ^ state[valueof(RATE_WORDS) + (j % (valueOf(CAPACITY) / 32))];
        state[i] = ct ? state[i] ^ z : z;
        state[j] = ct ? t : state[j] ^ t;
    end
    return tuple2(outbuf, state);
endfunction

typedef Bit#(TLog#(STEPS_BIG)) StepCounter;

typedef enum {
    Init,
    GetBdi,
    PadFullWord // pad extra word 0x00000080 to input buffer
} InputState deriving(Bits, Eq);

typedef enum {
    OpIdle,
    OpAbsorb,  // absorb RATE_WORDs of input buffer
    OpPermute, // run permutation with STEPS_BIG or STEPS_SLIM `sparkle_step`s
    OpGenTag   // generate tag
} OperationState deriving(Bits, Eq);


`ifdef DEBUG
`define SYNTH_CC
`endif

`ifdef SYNTH_CC
(* synthesize, doc="DEBUG enabled" *)
`endif
module mkSparkle(CryptoCoreIfc);
    SIPO#(RATE_WORDS, CoreWord) sipo <- mkSIPO;
    PISO#(RATE_WORDS, CoreWord) piso <- mkPISO;

    // FSM registers
    let inState <- mkReg(Init);
    let opState <- mkReg(OpIdle);

    Reg#(SparkleState) sparkleState           <- mkRegU;
    Reg#(Vector#(KEY_WORDS, CoreWord)) keyBuf <- mkRegU;
    Reg#(HeaderFlags)  inbufFlags             <- mkRegU;
    Reg#(StepCounter)  step                   <- mkRegU;
    Reg#(Bool)         incomplete             <- mkRegU;
    Reg#(Bool)         eoi                    <- mkRegU;
    Reg#(Bool)         slimPerm               <- mkRegU;

    // =================================================== Rules =================================================== //

    rule pad_after_full_word if (inState == PadFullWord);
        sipo.enq(32'h80, 0, True);
        inState <= inbufFlags.ptct ? Init : GetBdi;
    endrule

    (* fire_when_enabled *)
    rule absorb_inbuf if (opState == OpAbsorb);
        sipo.deq();
        match {.outbuf, .whiteState} = rho_whiten (inbufFlags.ct, inbufFlags.ad, sipo.isLastBlock, incomplete, sipo.data, sipo.valids, sparkleState);
        eoi <= inbufFlags.eoi && sipo.isLastBlock;
        slimPerm <= !inbufFlags.npub && !sipo.isLastBlock;
        if (inbufFlags.npub) begin
            sparkleState <= append(sipo.data, keyBuf); // first (from index 0) nonce, then key (from index RATE_WORDS)
        end else begin
            sparkleState <= whiteState;
            if (inbufFlags.ptct)
                piso.enq(outbuf, sipo.valids);
        end
        opState <= OpPermute;
        step    <= 0;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule permutate if (opState == OpPermute);
        sparkleState <= sparkle_step(sparkleState, step);
        step <= step + 1;
        if ((slimPerm && (step == fromInteger(valueof(STEPS_SLIM) - 1))) || (step == fromInteger(valueof(STEPS_BIG) - 1)))
            opState <= eoi ? OpGenTag : OpAbsorb;
    endrule

    (* fire_when_enabled *)
    rule squeeze_tag if (opState == OpGenTag);
        Vector#(TAG_WORDS, Word) tag = xorVecs(take(keyBuf), takeAt(valueof(RATE_WORDS), sparkleState));
        piso.enq(append(tag, replicate(?)), unpack(zeroExtend(16'hffff)));
        opState <= OpIdle;
    endrule

    // ================================================= Interface ================================================= //

    method Action initOp (OpFlags op) if (opState == OpIdle && inState == Init);
        if (!op.new_key) opState <= OpAbsorb;
        inState <= GetBdi;
    endmethod

    method Action key (w, lastWord) if (opState == OpIdle && inState != Init);
        keyBuf <= shiftInAtN(keyBuf, w);
        if (lastWord) opState <= OpAbsorb;
    endmethod
    
    method Action bdi (word, valid_bytes, last, flags) if (inState == GetBdi);
        inbufFlags <= flags;
        let incomp = msb(valid_bytes) == 0;
        let padExtraIfLast = !incomp && !sipo.oneShort;

        if (flags.empty) begin
            if (flags.ptct) inState <= Init;
        end else begin
            sipo.enq(padInWord80(word, valid_bytes), valid_bytes, last && !padExtraIfLast);
            incomplete <= incomp || !sipo.oneShort;

            if (last) begin
                if (padExtraIfLast) inState <= PadFullWord;
                else if (flags.ptct) inState <= Init;
            end
        end
    endmethod

    interface FifoOut bdo;
        method deq = piso.deq;
        method first = WithLast {data: piso.first, last: piso.isLast};
        method notEmpty = piso.notEmpty;
    endinterface
  
endmodule : mkSparkle

// ================================================== LWC Wrapper ========================================================

import LwcApi :: *;

(* synthesize *)
(* default_clock_osc = "clk", default_reset = "rst" *)
(* doc = "LWC top module" *)
module lwc (LwcIfc);
    let cc <- mkSparkle;
    let lwc <- mkLwc(cc, True, 16, 16, ?); // Little Ending, Key = 16 Bytes, Tag = 16 Bytes
    return lwc;
endmodule : lwc

endpackage : Sparkle
