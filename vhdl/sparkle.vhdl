--===================================================================================================================--
-- Author          Kamyar Mohajerani (kamyar@ieee.org)
-- Copyright       2021
-- VHDL Standard   2008
-- Description     Schwaemm and Esch: Lightweight Authenticated Encryption and Hashing using the Sparkle Permutation
-- TODO            Hashing (Esch) not implemented yet
--===================================================================================================================--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.numeric_std_unsigned.all;

use work.NIST_LWAPI_pkg.all;
use work.LWC_pkg.all;
use work.util_pkg.all;

entity sparkle is
  generic(
    IO_WIDTH         : positive := 32;  -- TODO only 32 supported!
    SPARKLE_RATE     : positive := 256;
    SPARKLE_CAPACITY : positive := 128
  );

  port(
    clk                  : in  std_logic;
    reset                : in  std_logic;
    --
    key_bits             : in  std_logic_vector(IO_WIDTH - 1 downto 0);
    key_valid            : in  std_logic;
    key_ready            : out std_logic;
    --
    key_update           : in  std_logic; --- ???
    --
    bdi                  : in  std_logic_vector(IO_WIDTH - 1 downto 0);
    bdi_last             : in  std_logic;
    bdi_validbytes       : in  std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
    bdi_type             : in  std_logic_vector(3 downto 0);
    bdi_eoi              : in  std_logic;
    bdi_valid            : in  std_logic;
    bdi_ready            : out std_logic;
    --
    decrypt_op           : in  std_logic;
    hash_op              : in  std_logic;
    --
    bdo_bits_word        : out std_logic_vector(IO_WIDTH - 1 downto 0);
    bdo_bits_last        : out std_logic;
    bdo_bits_valid_bytes : out std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
    bdo_bits_tag         : out std_logic;
    bdo_valid            : out std_logic;
    bdo_ready            : in  std_logic
  );

end sparkle;

architecture RTL of sparkle is
  constant KEY_LEN            : positive := 128;
  constant TAG_WORDS          : positive := 4;
  constant KEY_WORDS          : positive := KEY_LEN / 32;
  constant STATE_BITS         : positive := SPARKLE_RATE + SPARKLE_CAPACITY;
  constant STATE_BRANS        : positive := STATE_BITS / 64;
  constant STATE_WORDS        : positive := STATE_BITS / 32;
  constant RATE_WORDS         : positive := SPARKLE_RATE / 32;
  constant CAP_WORDS          : positive := SPARKLE_CAPACITY / 32;
  constant SPARKLE_STEPS_BIG  : positive := 11; -- 10, 11, 12
  constant SPARKLE_STEPS_SLIM : positive := 7; -- 8 for Sparkle512, o/w 7

  subtype rate_bytevalid_t is t_slv_array(0 to RATE_WORDS - 1)(3 downto 0);
  subtype rate_buffer_t is t_uint32_array(0 to RATE_WORDS - 1);
  subtype key_buffer_t is t_uint32_array(0 to KEY_WORDS - 1);
  subtype sparkle_state_t is t_uint32_array(0 to STATE_WORDS - 1);
  subtype step_t is unsigned(log2ceil(SPARKLE_STEPS_BIG) - 1 downto 0);

  type fsm_state_t is (INIT, PERMUTE, PROCESS_TEXT, FINALIZE_TAG);
  type rcon_t is array (0 to 7) of t_uint32;

  constant RCON : rcon_t := (
    X"B7E15162", X"BF715880", X"38B4DA56", X"324E7738",
    X"BB1185EB", X"4F7C7B57", X"CFBFA1C8", X"C2B3293D"
  );

  --======================================= Functions/Procedures ====================================================--
  procedure arxbox1(r1, r2 : in natural range 0 to 31; c : in t_uint32; x, y : inout t_uint32) is
  begin
    x := x + rotate_right(y, r1);
    y := y xor rotate_right(x, r2);
    x := x xor c;
  end procedure;

  procedure alzette(c : in t_uint32; x, y : inout t_uint32) is
  begin
    arxbox1(31, 24, c, x, y);
    arxbox1(17, 17, c, x, y);
    arxbox1(00, 31, c, x, y);
    arxbox1(24, 16, c, x, y);
  end procedure;

  function ell(x : t_uint32) return t_uint32 is
  begin
    return rotate_right(x xor shift_left(x, 16), 16);
  end function;

  procedure linear_layer(state : inout sparkle_state_t) is
    variable tmpx, tmpy, x0, y0 : t_uint32;
  begin
    tmpx                   := state(0);
    x0                     := state(0);
    tmpy                   := state(1);
    y0                     := state(1);
    for i in 1 to STATE_BRANS / 2 - 1 loop
      tmpx := tmpx xor state(i * 2);
      tmpy := tmpy xor state(i * 2 + 1);
    end loop;
    tmpx                   := ell(tmpx);
    tmpy                   := ell(tmpy);
    for i in 1 to STATE_BRANS / 2 - 1 loop
      state(i * 2 - 2)               := state(i * 2 + STATE_BRANS) xor state(i * 2) xor tmpy;
      state(i * 2 + STATE_BRANS)     := state(i * 2);
      state(i * 2 - 1)               := state(i * 2 + STATE_BRANS + 1) xor state(i * 2 + 1) xor tmpx;
      state(i * 2 + STATE_BRANS + 1) := state(i * 2 + 1);
    end loop;
    state(STATE_BRANS - 2) := state(STATE_BRANS) xor x0 xor tmpy;
    state(STATE_BRANS)     := x0;
    state(STATE_BRANS - 1) := state(STATE_BRANS + 1) xor y0 xor tmpx;
    state(STATE_BRANS + 1) := y0;
  end procedure;

  function sparkle_step(state : sparkle_state_t; step : step_t) return sparkle_state_t is
    constant sw : positive        := step'length;
    variable t  : sparkle_state_t := state;
  begin
    t(1)                  := t(1) xor RCON(to_integer(step(2 downto 0)));
    t(3)(sw - 1 downto 0) := t(3)(sw - 1 downto 0) xor step;
    for i in 0 to STATE_BRANS - 1 loop
      alzette(RCON(i), t(2 * i), t(2 * i + 1));
    end loop;
    linear_layer(t);
    return t;
  end function;

  function inbuf_word(w, xw : t_uint32; valid_bytes : std_logic_vector(3 downto 0); ct : boolean) return t_uint32 is
    variable word : t_uint32 := w;
  begin
    for i in 0 to 3 loop
      if ct and valid_bytes(i) = '0' then
        word(8 * (i + 1) - 1 downto 8 * i) := xw(8 * (i + 1) - 1 downto 8 * i);
      end if;
    end loop;
    return word;
  end function;

  function padword(word        : std_logic_vector(IO_WIDTH - 1 downto 0);
                   valid_bytes : std_logic_vector(IO_WIDTH/8 - 1 downto 0);
                   pad_0x80    : BOOLEAN
                  ) return std_logic_vector is
    variable ret : std_logic_vector(IO_WIDTH - 1 downto 0) := word;
  begin
    for i in valid_bytes'range loop
      if valid_bytes(i) = '0' then
        ret(8 * (i + 1) - 1 downto 8 * i) := (others => '0');
        if pad_0x80 and i > 0 and valid_bytes(i - 1) = '1' then
          ret(8 * (i + 1) - 1) := '1';
        end if;
      end if;
    end loop;
    return ret;
  end function;

  procedure rho_whi(ct              : in boolean;
                    ad              : in boolean;
                    last_block      : in boolean;
                    incomplete      : in boolean;
                    inbuf           : in rate_buffer_t;
                    inbuf_bytevalid : in rate_bytevalid_t;
                    instate         : in sparkle_state_t;
                    outbuf          : out rate_buffer_t;
                    outstate        : out sparkle_state_t) is
    variable in_xor_state : rate_buffer_t;
    variable wi, wj, z, t : t_uint32;
    variable const_x      : integer;
    variable j            : natural;
    variable state        : sparkle_state_t := instate;
  begin
    if last_block then
      if ad then
        const_x := 4 when incomplete else 5;
      else
        const_x := 6 when incomplete else 7;
      end if;
      j                                   := 24 + 3 - 1;
      state(STATE_WORDS - 1)(j downto 24) := state(STATE_WORDS - 1)(j downto 24) xor to_unsigned(const_x, 3);
    end if;

    for i in 0 to RATE_WORDS - 1 loop
      in_xor_state(i) := inbuf(i) xor state(i);
    end loop;
    for i in 0 to RATE_WORDS / 2 - 1 loop
      j  := i + RATE_WORDS / 2;
      wi := inbuf_word(inbuf(i), in_xor_state(i), inbuf_bytevalid(i), ct);
      wj := inbuf_word(inbuf(j), in_xor_state(j), inbuf_bytevalid(j), ct);
      z  := state(j) xor wi xor state(RATE_WORDS + i);
      t  := state(i) xor wj xor state(RATE_WORDS + (j mod CAP_WORDS));

      if ct then
        state(i) := state(i) xor z;
        state(j) := t;
      else
        state(i) := z;
        state(j) := state(j) xor t;
      end if;

      outbuf(i) := in_xor_state(i);
      outbuf(j) := in_xor_state(j);
    end loop;
    outstate := state;
  end procedure;

  --============================================ Registers ==========================================================--
  signal sparkle_state                                            : sparkle_state_t;
  signal inbuf_validbytes                                         : rate_bytevalid_t;
  signal step_cnt                                                 : step_t;
  signal state, post_perm_state                                   : fsm_state_t;
  signal perm_slim_steps, inbuf_ct, inbuf_hm, inbuf_ad, inbuf_eoi : boolean;
  signal outbuf_tag, outbuf_tagverif                              : boolean;

  --============================================== Wires ============================================================--
  signal keybuf_slva                           : t_slv_array(0 to KEY_WORDS - 1)(IO_WIDTH - 1 downto 0);
  signal inbuf_slva, outbuf_slva               : t_slv_array(0 to RATE_WORDS - 1)(IO_WIDTH - 1 downto 0);
  signal input_word, output_word               : std_logic_vector(IO_WIDTH - 1 downto 0);
  signal output_validbytes                     : std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
  signal keybuf                                : key_buffer_t;
  signal inbuf, outbuf                         : rate_buffer_t;
  signal rho_whitened_state                    : sparkle_state_t;
  signal inbuf_valid, inbuf_ready              : std_logic;
  signal inbuf_valid_words, outbuf_valid_words : t_bit_array(0 to RATE_WORDS - 1);
  signal keybuf_valid, keybuf_ready            : std_logic;
  signal outbuf_valid, outbuf_ready            : std_logic;
  signal inbuf_last, inbuf_incomp              : std_logic;
  signal outbuf_last                           : std_logic;
begin
  --============================================ Submodules =========================================================--
  INBUF_SIPO : entity work.SIPO
    generic map(
      WORD_WIDTH       => IO_WIDTH,
      NUM_WORDS        => RATE_WORDS,
      WITH_VALID_BYTES => TRUE,
      ZERO_FILL        => TRUE,
      PADDING_BYTE     => X"80",
      PIPELINED        => TRUE
    )
    port map(
      clk                  => clk,
      reset                => reset,
      in_bits_word         => input_word,
      in_bits_last         => bdi_last,
      in_bits_valid_bytes  => bdi_validbytes,
      in_valid             => bdi_valid,
      in_ready             => bdi_ready,
      out_bits_block       => inbuf_slva,
      out_bits_valid_words => inbuf_valid_words,
      out_bits_bva         => inbuf_validbytes,
      out_bits_last        => inbuf_last,
      out_bits_incomp      => inbuf_incomp,
      out_valid            => inbuf_valid,
      out_ready            => inbuf_ready
    );

  KEY_SIPO : entity work.SIPO
    generic map(
      WORD_WIDTH       => IO_WIDTH,
      NUM_WORDS        => KEY_WORDS,
      WITH_VALID_BYTES => FALSE,
      ZERO_FILL        => FALSE,
      PADDING_BYTE     => (others => '0'),
      PIPELINED        => TRUE
    )
    port map(
      clk                  => clk,
      reset                => reset,
      in_bits_word         => key_bits,
      in_bits_last         => '0',      -- ignored
      in_bits_valid_bytes  => (others => '-'), -- ignored
      in_valid             => key_valid,
      in_ready             => key_ready,
      out_bits_block       => keybuf_slva,
      out_bits_valid_words => open,     -- ignored
      out_bits_bva         => open,     -- ignored
      out_bits_last        => open,     -- ignored
      out_bits_incomp      => open,     -- ignored
      out_valid            => keybuf_valid,
      out_ready            => keybuf_ready
    );

  OUTBUF_PISO : entity work.PISO
    generic map(
      WORD_WIDTH       => IO_WIDTH,
      NUM_WORDS        => RATE_WORDS,
      WITH_VALID_BYTES => TRUE
    )
    port map(
      clk                  => clk,
      reset                => reset,
      in_bits_block        => outbuf_slva,
      in_bits_valid_words  => outbuf_valid_words,
      in_bits_valid_bytes  => inbuf_validbytes, -- for TAG and DIGEST we ignore out_bits_valid_bytes
      in_bits_last         => outbuf_last,
      in_valid             => outbuf_valid,
      in_ready             => outbuf_ready,
      out_bits_word        => output_word,
      out_bits_last        => bdo_bits_last,
      out_bits_valid_bytes => output_validbytes,
      out_valid            => bdo_valid,
      out_ready            => bdo_ready
    );

  --============================================== Assigns ==========================================================--
  keybuf               <= to_uint32_array(keybuf_slva);
  inbuf                <= to_uint32_array(inbuf_slva);
  outbuf_slva          <= to_slva(outbuf);
  input_word           <= padword(bdi, bdi_validbytes, TRUE);
  --
  bdo_bits_tag         <= to_std_logic(outbuf_tagverif);
  bdo_bits_valid_bytes <= (others => '1') when outbuf_tag else output_validbytes;
  bdo_bits_word        <= padword(output_word, bdo_bits_valid_bytes, FALSE);

  --============================================ Processes ==========================================================--

  COMB_PROC : process(all)
    variable tmp_outbuf : rate_buffer_t;
    variable tagbuf     : t_uint32_array(0 to TAG_WORDS - 1);
    variable tmp_state  : sparkle_state_t;
  begin
    rho_whi(
      inbuf_ct, inbuf_ad, inbuf_last = '1', inbuf_incomp = '1', inbuf, inbuf_validbytes, sparkle_state,
      tmp_outbuf, tmp_state
    );
    for i in 0 to TAG_WORDS - 1 loop
      tagbuf(i) := sparkle_state(RATE_WORDS + i) xor keybuf(i);
    end loop;
    outbuf_last        <= inbuf_last;
    outbuf             <= tmp_outbuf;
    outbuf_valid_words <= inbuf_valid_words;
    rho_whitened_state <= tmp_state;
    inbuf_ready        <= '0';
    keybuf_ready       <= '0';
    outbuf_valid       <= '0';
    case state is
      when INIT =>                      -- load npub and optionally key
        inbuf_ready  <= keybuf_valid and not key_update;
        keybuf_ready <= key_update;     -- ???
      when PROCESS_TEXT =>
        inbuf_ready  <= to_std_logic(inbuf_ad) or outbuf_ready;
        outbuf_valid <= not to_std_logic(inbuf_ad) and inbuf_valid;
      when PERMUTE =>
        null;
      when FINALIZE_TAG =>
        outbuf(0 to TAG_WORDS - 1) <= tagbuf;
        outbuf_valid_words         <= (X"F", others => '0');
        outbuf_last                <= '1';
        outbuf_valid               <= '1';
    end case;
  end process;

  FLAG_REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      -- keep value of these flags associated with the last received bdi word
      if bdi_valid = '1' and bdi_ready = '1' then
        inbuf_ad  <= bdi_type = HDR_AD;
        inbuf_eoi <= bdi_eoi = '1';
      end if;
    end if;
  end process;

  inbuf_hm <= hash_op = '1';
  inbuf_ct <= decrypt_op = '1' and not inbuf_ad;

  REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state <= INIT;
      else
        case state is
          when INIT =>
            if inbuf_valid = '1' and inbuf_ready = '1' then -- implies keybuf_valid = '1'
              sparkle_state   <= inbuf & keybuf; -- first nonce then key
              step_cnt        <= (others => '0');
              state           <= PERMUTE;
              perm_slim_steps <= FALSE;
              post_perm_state <= FINALIZE_TAG when inbuf_eoi else PROCESS_TEXT;
            end if;
          when PERMUTE =>
            sparkle_state <= sparkle_step(sparkle_state, step_cnt);
            step_cnt      <= step_cnt + 1;
            if (perm_slim_steps and (step_cnt = (SPARKLE_STEPS_SLIM - 1))) or step_cnt = (SPARKLE_STEPS_BIG - 1) then
              step_cnt <= (others => '0');
              state    <= post_perm_state;
            end if;
          when PROCESS_TEXT =>
            if inbuf_valid = '1' and (inbuf_ad or outbuf_ready = '1') then
              sparkle_state   <= rho_whitened_state;
              perm_slim_steps <= inbuf_last = '0';
              state           <= PERMUTE;
              post_perm_state <= state when inbuf_last = '0' or (inbuf_ad and not inbuf_eoi) else FINALIZE_TAG;
            end if;
            if outbuf_valid and outbuf_ready then -- outbuf is empty (or will be)
              outbuf_tag      <= FALSE; -- overriden in FINALIZE_TAG
              outbuf_tagverif <= FALSE; -- overriden in FINALIZE_TAG
            end if;
          when FINALIZE_TAG =>
            if outbuf_ready = '1' then
              outbuf_tag      <= TRUE;
              outbuf_tagverif <= decrypt_op = '1';
              state           <= INIT;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture RTL;
