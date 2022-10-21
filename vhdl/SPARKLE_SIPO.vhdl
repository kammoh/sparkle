--===================================================================================================================--
-- Author:         Kamyar Mohajerani
-- VHDL Standard:  2008
-- Description:    Shift-register-based piplelined SIPO (Serial-In-Parallel-Out)
--                 features:
--                     - PIPELINED: simultanous dequeue and enqueue when full 
--                     - ZERO_FILL: automatically zero fills upon recieving last word
--                     - WITH_BYTE_VALIDS: store track of valid bytes in each word
--
--===================================================================================================================--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.util_pkg.all;

entity SPARKLE_SIPO is
  generic(
    WORD_WIDTH       : positive                     := 32;              -- width of each word in bits
    NUM_WORDS        : positive                     := 8;               -- depth
    WITH_VALID_BYTES : boolean                      := FALSE;           -- if  for each byte a valid flag is stored
    ZERO_FILL        : boolean                      := FALSE;           -- When `in_bits_last` fill `m` remaining free space with zeros in `m` clock cycles
    PADDING_BYTE     : unsigned(7 downto 0) := (others => '0'); -- padding byte
    PIPELINED        : boolean                      := TRUE             -- simultanous dequeue and enqueue when full
  );
  port(
    clk                  : in  std_logic;
    reset                : in  std_logic;
    --
    in_bits_word         : in  std_logic_vector(WORD_WIDTH - 1 downto 0);
    in_bits_last         : in  std_logic; -- ignored if ZERO_FILL = FALSE
    in_bits_valid_bytes  : in  std_logic_vector(WORD_WIDTH / 8 - 1 downto 0); -- valid bytes in a word
    in_valid             : in  std_logic;
    in_ready             : out std_logic;
    --
    out_bits_block       : out t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0);
    out_bits_valid_words : out t_bit_array(0 to NUM_WORDS - 1); -- each bit shows the word is valid at all or not (could be empty, but valid!)
    out_bits_bva         : out t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0); -- array of valid bytes
    out_bits_last        : out std_logic;
    out_bits_incomp      : out std_logic; -- incomplete block (only if WITH_BYTE_VALIDS = TRUE)
    out_valid            : out std_logic;
    out_ready            : in  std_logic
  );
end entity SPARKLE_SIPO;

architecture RTL of SPARKLE_SIPO is
  --============================================ Registers ==========================================================--
  signal block_reg               : t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0);
  signal validbytes              : t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0);
  signal word_valids             : t_bit_array(0 to NUM_WORDS - 1);
  signal fill_zeros              : boolean;
  signal last                    : std_logic;
  signal do_pad_byte, incomplete : boolean;

  --============================================= Wires =============================================================--
  signal do_enq, do_deq, do_shiftin, full, one_short : boolean;
  signal next_word                                   : std_logic_vector(WORD_WIDTH - 1 downto 0);
  signal next_validbytes                             : std_logic_vector(WORD_WIDTH / 8 - 1 downto 0);

begin
  full      <= word_valids(0) = '1';
  one_short <= word_valids(1) = '1';    -- max 1 short (or full)
  do_enq    <= in_valid = '1' and in_ready = '1';
  do_deq    <= out_valid = '1' and out_ready = '1';

  out_valid       <= '1' when full else '0';
  out_bits_last   <= last;
  out_bits_incomp <= '1' when incomplete else '0';

  COMB_PROC : process(all)
  begin
    -- VHDL is cursed!
    -- can't do: out_bits_block <= block_reg;
    for i in 0 to NUM_WORDS - 1 loop
      out_bits_block(i) <= block_reg(i);
    end loop;
  end process;
  out_bits_valid_words <= word_valids;

  GEN_FILL_ZERO : if ZERO_FILL generate
    GEM_PIPELINED_FZ : if PIPELINED generate
      in_ready <= '1' when not fill_zeros and (not full or do_deq) else '0';
    else generate
      in_ready <= '1' when not fill_zeros and not full else '0';
    end generate;

    next_word <= in_bits_word when not fill_zeros else std_logic_vector(resize(PADDING_BYTE, next_word'length)) when do_pad_byte else (others => '0');

    process(clk)
    begin
      if rising_edge(clk) then
        if reset = '1' then
          fill_zeros <= FALSE;
        else
          if do_deq or one_short then   -- one_short: either through do_enq or fill_zeros
            fill_zeros <= FALSE;
          end if;
          do_pad_byte <= FALSE;
          if do_enq then
            if in_bits_last = '1' and (not one_short or do_deq) then
              do_pad_byte <= in_bits_valid_bytes(WORD_WIDTH / 8 - 1) = '1';
              fill_zeros  <= TRUE;
            end if;
          end if;
        end if;
      end if;
    end process;
  else generate                         -- no zero filling
    GEM_PIPELINED_NFZ : if PIPELINED generate
      in_ready <= '1' when not full or do_deq else '0';
    else generate                       -- not pipelined either
      in_ready <= '1' when not full else '0';
    end generate;
    fill_zeros <= FALSE;
    next_word  <= in_bits_word;
  end generate;

  GEN_WITH_BYTE_VALIDS : if WITH_VALID_BYTES generate
    next_validbytes <= (others => '0') when fill_zeros else in_bits_valid_bytes;

    process(clk)
    begin
      if rising_edge(clk) then
        if do_enq then
          incomplete <= ((not one_short or do_deq) and in_bits_last = '1') or in_bits_valid_bytes(WORD_WIDTH / 8 - 1) = '0';
        end if;
        if do_shiftin then
          validbytes <= validbytes(1 to validbytes'high) & next_validbytes;
        end if;
      end if;
    end process;
    -- VHDL is cursed!
    -- can't do: out_bits_bva <= bytevalids;
    out_bits_bva_PROC : process(all)
    begin
      for i in 0 to NUM_WORDS - 1 loop
        out_bits_bva(i) <= validbytes(i);
      end loop;
    end process;
  else generate                         -- no per-byte support
    out_bits_bva <= (others => (others => '-'));
  end generate;

  do_shiftin <= fill_zeros or do_enq;

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        word_valids <= (others => '0');
      else
        if do_shiftin then
          block_reg <= block_reg(1 to block_reg'high) & next_word;
        end if;
        if fill_zeros then              -- optimized-out when ZERO_FILL = FALSE
          word_valids <= word_valids(1 to word_valids'high) & '0'; -- FIXME this is probably wrong! should be '1' (and remove out_bits_valid_words)! word_valids is a gauge!
        end if;
        if do_enq then
          last <= in_bits_last;
          if do_deq then                -- enq _and_ deq
            word_valids <= (1 to word_valids'high => '0') & '1';
          else
            word_valids <= word_valids(1 to word_valids'high) & '1';
          end if;
        elsif do_deq then
          word_valids <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture;
