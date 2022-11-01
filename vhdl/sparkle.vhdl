--===================================================================================================================--
-- Author          Kamyar Mohajerani (kamyar@ieee.org)
-- Copyright       2021
-- VHDL Standard   2008
-- Description     Schwaemm and Esch: Lightweight Authenticated Encryption and Hashing using the Sparkle Permutation
-- TODO            Hashing (Esch)
--===================================================================================================================--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.numeric_std_unsigned.all;

use work.NIST_LWAPI_pkg.all;
use work.util_pkg.all;

entity sparkle is
  generic(
    IO_WIDTH : positive := 32
  );

  port(
    --# {{clocks|}}
    clk             : in  std_logic;
    reset           : in  std_logic;
    --# {{bus(#f2d7c6)|}}
    key             : in  std_logic_vector(IO_WIDTH - 1 downto 0);
    key_valid       : in  std_logic;
    key_ready       : out std_logic;
    --
    key_update      : in  std_logic;    --- ???
    --# {{bus(#9996a5)|}}
    bdi             : in  std_logic_vector(IO_WIDTH - 1 downto 0);
    bdi_last        : in  std_logic;
    bdi_validbytes  : in  std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
    bdi_type        : in  std_logic_vector(3 downto 0);
    bdi_eoi         : in  std_logic;
    bdi_valid       : in  std_logic;
    bdi_ready       : out std_logic;
    --
    decrypt_op      : in  std_logic;
    hash_op         : in  std_logic;
    --# {{bus(#e0bbb6)|}}
    bdo             : out std_logic_vector(IO_WIDTH - 1 downto 0);
    bdo_last        : out std_logic;
    bdo_valid_bytes : out std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
    bdo_tagverif    : out std_logic;
    bdo_valid       : out std_logic;
    bdo_ready       : in  std_logic
  );

end sparkle;

architecture RTL of sparkle is
  constant KEY_LEN            : positive := 128;
  constant TAG_WORDS          : positive := 4;
  constant KEY_WORDS          : positive := KEY_LEN / 32;
  constant STATE_BITS         : positive := 384;
  constant STATE_BRANS        : positive := STATE_BITS / 64;
  constant STATE_WORDS        : positive := STATE_BITS / 32;
  constant HASH_RATE_WORDS    : positive := 128 / 32;
  constant AEAD_RATE_WORDS    : positive := 256 / 32;
  constant MAX_RATE_WORDS     : positive := maximum(HASH_RATE_WORDS, AEAD_RATE_WORDS);
  constant AEAD_CAP_WORDS     : positive := STATE_WORDS - AEAD_RATE_WORDS;
  constant SPARKLE_STEPS_BIG  : positive := 11; --! 10, 11, 12
  constant SPARKLE_STEPS_SLIM : positive := 7; --! 8 for Sparkle512, otherwise 7

  subtype t_rate_bytevalid is t_slv_array(0 to MAX_RATE_WORDS - 1)(3 downto 0);
  subtype t_rate_buffer is t_uint32_array(0 to MAX_RATE_WORDS - 1);
  subtype t_key_buffer is t_uint32_array(0 to KEY_WORDS - 1);
  subtype t_sparkle_state is t_uint32_array(0 to STATE_WORDS - 1);
  subtype t_step_counter is unsigned(log2ceil(SPARKLE_STEPS_BIG) - 1 downto 0);

  type t_fsm is (S_INIT, S_PERMUTE, S_PROCESS_TEXT, S_TAG, S_DIGEST);
  type t_rcon is array (0 to 7) of t_uint32;

  constant ROUND_CONSTANTS : t_rcon := (
    X"B7E15162", X"BF715880", X"38B4DA56", X"324E7738",
    X"BB1185EB", X"4F7C7B57", X"CFBFA1C8", X"C2B3293D"
  );                                    --! round constants

  --======================================= Functions/Procedures ====================================================--
  --! Single-word ARX
  procedure arxbox(r1, r2 : in natural range 0 to 31; c : in t_uint32; x, y : inout t_uint32) is
  begin
    x := x + rotate_right(y, r1);
    y := y xor rotate_right(x, r2);
    x := x xor c;
  end procedure;

  --! Single-word Alzette
  procedure alzette(c : in t_uint32; x, y : inout t_uint32) is
  begin
    arxbox(31, 24, c, x, y);
    arxbox(17, 17, c, x, y);
    arxbox(00, 31, c, x, y);
    arxbox(24, 16, c, x, y);
  end procedure;

  --! Single-word linear transfor
  function ell(x : t_uint32) return t_uint32 is
  begin
    return rotate_right(x xor shift_left(x, 16), 16);
  end function;

  procedure linear_layer(state : inout t_sparkle_state) is
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

  function sparkle_step(state : t_sparkle_state; step : t_step_counter) return t_sparkle_state is
    constant sw : positive        := step'length;
    variable t  : t_sparkle_state := state;
  begin
    t(1)                  := t(1) xor ROUND_CONSTANTS(to_integer(step(2 downto 0)));
    t(3)(sw - 1 downto 0) := t(3)(sw - 1 downto 0) xor step;
    for i in 0 to t'length / 2 - 1 loop
      alzette(ROUND_CONSTANTS(i), t(2 * i), t(2 * i + 1));
    end loop;
    linear_layer(t);
    return t;
  end function;

  function inbuf_word_masked(w, xw : t_uint32; valid_bytes : std_logic_vector(3 downto 0); ct : boolean) return t_uint32 is
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
                   pad_0x80    : boolean
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

  procedure rho_whi_or_addmsg(ct              : in boolean;
                              ad              : in boolean;
                              hm              : in boolean;
                              last_block      : in std_logic;
                              incomplete      : in std_logic;
                              inbuf           : in t_rate_buffer;
                              inbuf_bytevalid : in t_rate_bytevalid;
                              instate         : in t_sparkle_state;
                              outbuf          : out t_rate_buffer;
                              outstate        : out t_sparkle_state) is
    variable in_xor_state             : t_rate_buffer;
    variable wi, wj, z, t, tmpx, tmpy : t_uint32;
    variable j                        : natural;
    variable const_x                  : unsigned(2 downto 0);
    variable state                    : t_sparkle_state := instate;
  begin
    if hm then
      if incomplete then
        const_x := "001";
      else
        const_x := "010";
      end if;
    else
      const_x := '1' & not to_std_logic(ad) & not incomplete;
    end if;

    if last_block = '1' then
      state(STATE_WORDS - 1)(26 downto 24) := state(STATE_WORDS - 1)(26 downto 24) xor const_x;
    end if;

    for i in 0 to HASH_RATE_WORDS - 1 loop
      in_xor_state(i) := inbuf(i) xor state(i);
    end loop;
    for i in HASH_RATE_WORDS to AEAD_RATE_WORDS - 1 loop
      if hm then
        in_xor_state(i) := state(i);
      else
        in_xor_state(i) := inbuf(i) xor state(i);
      end if;
    end loop;
    outbuf := in_xor_state;

    for i in 0 to AEAD_RATE_WORDS / 2 - 1 loop
      j  := i + AEAD_RATE_WORDS / 2;
      wi := inbuf_word_masked(inbuf(i), in_xor_state(i), inbuf_bytevalid(i), ct);
      wj := inbuf_word_masked(inbuf(j), in_xor_state(j), inbuf_bytevalid(j), ct);
      z  := state(j) xor wi xor state(AEAD_RATE_WORDS + i);
      t  := state(i) xor wj xor state(AEAD_RATE_WORDS + (j mod AEAD_CAP_WORDS));

      if ct then
        state(i) := state(i) xor z;
        state(j) := t;
      else
        state(i) := z;
        state(j) := state(j) xor t;
      end if;
    end loop;

    tmpx := inbuf(0);
    tmpy := inbuf(1);
    for i in 1 to STATE_WORDS / 4 loop
      tmpx := tmpx xor inbuf(2 * i);
      tmpy := tmpy xor inbuf(2 * i + 1);
    end loop;

    if hm then
      for i in 0 to STATE_BRANS / 2 - 1 loop
        outstate(2 * i)     := in_xor_state(2 * i) xor ell(tmpy);
        outstate(2 * i + 1) := in_xor_state(2 * i + 1) xor ell(tmpx);
      end loop;
    else
      outstate := state;
    end if;

  end procedure;

  --============================================ Registers ==========================================================--
  signal sparkle_state                                                  : t_sparkle_state;
  signal inbuf_validbytes                                               : t_rate_bytevalid;
  signal step_counter                                                   : t_step_counter;
  signal state                                                          : t_fsm; --! FSM state
  signal perm_slim_steps, inbuf_ct, inbuf_ad, inbuf_eoi                 : boolean;
  signal hash_mode, dec_mode                                            : boolean;
  signal outbuf_tag_or_digest, outbuf_tagverif, final_perm, digest_last : boolean;

  --============================================== Wires ============================================================--
  signal keybuf_slva                           : t_slv_array(0 to KEY_WORDS - 1)(IO_WIDTH - 1 downto 0);
  signal inbuf_slva, outbuf_slva               : t_slv_array(0 to MAX_RATE_WORDS - 1)(IO_WIDTH - 1 downto 0);
  signal input_word, output_word               : std_logic_vector(IO_WIDTH - 1 downto 0);
  signal output_validbytes                     : std_logic_vector(IO_WIDTH / 8 - 1 downto 0);
  signal keybuf                                : t_key_buffer;
  signal inbuf, outbuf                         : t_rate_buffer;
  signal rho_whitened_state                    : t_sparkle_state;
  signal inbuf_valid, inbuf_ready              : std_logic;
  signal inbuf_valid_words, outbuf_valid_words : t_bit_array(0 to MAX_RATE_WORDS - 1);
  signal keybuf_valid, keybuf_ready            : std_logic;
  signal outbuf_valid, outbuf_ready            : std_logic;
  signal inbuf_last, inbuf_incomp              : std_logic;
  signal outbuf_last                           : std_logic;
  signal last_step                             : boolean;
begin
  --============================================ Submodules =========================================================--
  INBUF_SIPO : entity work.SPARKLE_SIPO
    generic map(
      WORD_WIDTH       => IO_WIDTH,
      NUM_WORDS        => MAX_RATE_WORDS,
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

  KEY_SIPO : entity work.SPARKLE_SIPO
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
      in_bits_word         => key,
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

  OUTBUF_PISO : entity work.SPARKLE_PISO
    generic map(
      WORD_WIDTH       => IO_WIDTH,
      NUM_WORDS        => MAX_RATE_WORDS,
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
      out_bits_last        => bdo_last,
      out_bits_valid_bytes => output_validbytes,
      out_valid            => bdo_valid,
      out_ready            => bdo_ready
    );

  --============================================== Assigns ==========================================================--
  keybuf          <= to_uint32_array(keybuf_slva);
  inbuf           <= to_uint32_array(inbuf_slva);
  outbuf_slva     <= to_slva(outbuf);
  input_word      <= padword(bdi, bdi_validbytes, TRUE);
  last_step       <= (perm_slim_steps and (step_counter = (SPARKLE_STEPS_SLIM - 1))) or step_counter = (SPARKLE_STEPS_BIG - 1);
  --
  bdo_tagverif    <= to_std_logic(outbuf_tagverif);
  bdo_valid_bytes <= (others => '1') when outbuf_tag_or_digest else output_validbytes;
  bdo             <= padword(output_word, bdo_valid_bytes, FALSE);

  --============================================ Processes ==========================================================--

  COMB_PROC : process(all)
    variable tmp_outbuf : t_rate_buffer;
    variable tagbuf     : t_uint32_array(0 to TAG_WORDS - 1);
    variable tmp_state  : t_sparkle_state;
  begin
    rho_whi_or_addmsg(
      inbuf_ct, inbuf_ad, hash_mode, inbuf_last, inbuf_incomp, inbuf, inbuf_validbytes, sparkle_state,
      tmp_outbuf, tmp_state
    );

    for i in 0 to TAG_WORDS - 1 loop
      tagbuf(i) := sparkle_state(AEAD_RATE_WORDS + i) xor keybuf(i);
    end loop;

    outbuf_last        <= inbuf_last;
    outbuf             <= tmp_outbuf;
    outbuf_valid_words <= inbuf_valid_words;
    rho_whitened_state <= tmp_state;
    inbuf_ready        <= '0';
    keybuf_ready       <= '0';
    outbuf_valid       <= '0';

    case state is
      when S_INIT =>
        -- if bdo_valid = '0' then
        -- load npub and optionally key
        inbuf_ready  <= keybuf_valid and not key_update;
        keybuf_ready <= key_update;     -- ???
      -- end if;

      when S_PROCESS_TEXT =>
        inbuf_ready  <= to_std_logic(inbuf_ad) or outbuf_ready;
        outbuf_valid <= not to_std_logic(inbuf_ad) and inbuf_valid;

      when S_PERMUTE =>
        null;

      when S_TAG =>
        outbuf(0 to TAG_WORDS - 1) <= tagbuf;
        outbuf_valid_words         <= (X"F", others => '0');
        outbuf_last                <= '1';
        outbuf_valid               <= '1';

      when S_DIGEST =>
        outbuf(0 to TAG_WORDS - 1) <= tagbuf;
        outbuf_valid_words         <= (X"F", others => '0');
        outbuf_last                <= to_std_logic(digest_last);
        outbuf_valid               <= '1';

    end case;

  end process;

  REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      -- keep value of these flags associated with the last received bdi word
      if bdi_valid = '1' and bdi_ready = '1' then
        inbuf_ad  <= bdi_type = HDR_AD;
        inbuf_ct  <= bdi_type = HDR_CT; -- TODO optimize?
        inbuf_eoi <= bdi_eoi = '1';
      end if;

      if reset = '1' then
        state <= S_INIT;
      else
        case state is
          when S_INIT =>
            digest_last <= FALSE;
            final_perm  <= inbuf_eoi;
            -- if bdo_valid = '0' then
            if inbuf_valid = '1' and inbuf_ready = '1' then -- implies keybuf_valid = '1'
              sparkle_state   <= inbuf & keybuf; -- first nonce then key
              step_counter    <= (others => '0');
              state           <= S_PERMUTE;
              perm_slim_steps <= FALSE;
            end if;
            -- end if;

            hash_mode <= hash_op = '1';
            dec_mode  <= decrypt_op = '1';

          when S_PERMUTE =>
            sparkle_state <= sparkle_step(sparkle_state, step_counter);
            step_counter      <= step_counter + 1;
            if last_step then
              if final_perm then
                state <= S_DIGEST when hash_mode else S_TAG;
              else
                state <= S_PROCESS_TEXT;
              end if;
            end if;

          when S_PROCESS_TEXT =>
            step_counter <= (others => '0');
            if inbuf_valid = '1' and (inbuf_ad or outbuf_ready = '1') then
              sparkle_state   <= rho_whitened_state;
              perm_slim_steps <= inbuf_last = '0';

              state           <= S_PERMUTE;
              final_perm      <= inbuf_last = '1' and (not inbuf_ad or inbuf_eoi);
            end if;
            if outbuf_valid and outbuf_ready then -- update IFF outbuf is loaded
              outbuf_tag_or_digest <= FALSE; -- overriden in FINALIZE_TAG
              outbuf_tagverif      <= FALSE; -- overriden in FINALIZE_TAG
            end if;

          when S_TAG =>
            if outbuf_ready then
              outbuf_tag_or_digest <= TRUE;
              outbuf_tagverif      <= dec_mode;
              state                <= S_INIT;
            end if;

          when S_DIGEST =>
            step_counter <= (others => '0');
            if outbuf_ready then
              outbuf_tag_or_digest <= TRUE;
              digest_last          <= TRUE;
              state                <= S_INIT when digest_last else S_PERMUTE;
            end if;

        end case;

      end if;
    end if;
  end process;
end architecture RTL;
