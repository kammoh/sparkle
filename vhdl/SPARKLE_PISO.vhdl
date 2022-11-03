--===================================================================================================================--
-- Author:         Kamyar Mohajerani
-- VHDL Standard:  2008
--
--===================================================================================================================--
library IEEE;
use IEEE.std_logic_1164.all;

use work.util_pkg.all;

entity SPARKLE_PISO is
  generic(
    WORD_WIDTH       : positive;
    NUM_WORDS        : positive;
    WITH_VALID_BYTES : boolean
  );
  port(
    clk             : in  std_logic;
    reset           : in  std_logic;
    --
    in_data         : in  t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0);
    in_valid_words  : in  t_bit_array(0 to NUM_WORDS - 1);
    in_valid_bytes  : in  t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0);
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;
    --
    out_data        : out std_logic_vector(WORD_WIDTH - 1 downto 0);
    out_last        : out std_logic;
    out_valid_bytes : out std_logic_vector(WORD_WIDTH / 8 - 1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic
  );
end entity SPARKLE_PISO;

architecture RTL of SPARKLE_PISO is
  --============================================ Registers ==========================================================--
  signal data_block : t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0);
  signal validwords : t_bit_array(0 to NUM_WORDS - 1);
  signal validbytes : t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0);
  signal last_block : std_logic;

  --============================================== Wires ============================================================--
  signal do_enq, do_deq, empty, last_or_empty : boolean;

begin
  empty         <= validwords(0) /= '1';
  do_enq        <= in_valid = '1' and in_ready = '1';
  do_deq        <= out_valid = '1' and out_ready = '1';
  last_or_empty <= validwords(1) /= '1';
  in_ready      <= '1' when empty or (last_or_empty and do_deq) else '0';
  out_valid     <= '0' when empty else '1';
  out_data      <= data_block(0);
  out_last      <= '1' when last_block = '1' and last_or_empty else '0'; -- correct if out_valid

  GEN_WITH_VALID_BYTES : if WITH_VALID_BYTES generate
    out_valid_bytes <= validbytes(0);

    VALIDBYTES_PROC : process(clk)
    begin
      if rising_edge(clk) then
        if do_enq then
          validbytes <= in_valid_bytes;
        elsif do_deq then
          validbytes(0 to validbytes'high - 1) <= validbytes(1 to validbytes'high);
        end if;
      end if;
    end process;
  else generate
    out_valid_bytes <= (others => '-');
  end generate;

  VALIDWORDS_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        validwords(0) <= '0';
      else
        if do_enq then                  -- enq or enq+deq
          validwords <= in_valid_words;
        elsif do_deq then
          validwords <= validwords(1 to validwords'high) & '0';
        end if;
      end if;
    end if;
  end process;

  DATABLOCK_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if do_enq then                    -- enq or enq+deq
        data_block <= in_data;
        last_block <= in_last;
      elsif do_deq then
        data_block(0 to data_block'high - 1) <= data_block(1 to data_block'high);
      end if;
    end if;
  end process;
end architecture;
