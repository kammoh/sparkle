library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.design_pkg.all;
use work.NIST_LWAPI_pkg.all;
use work.util_pkg.all;

entity cryptocore is
  port(
    clk             : in  std_logic;
    rst             : in  std_logic;
    ----!key----------------------------------------------------
    key             : in  std_logic_vector(CCW - 1 downto 0);
    key_valid       : in  std_logic;
    key_ready       : out std_logic;
    key_update      : in  std_logic;
    ----!Data----------------------------------------------------
    bdi             : in  std_logic_vector(CCW - 1 downto 0);
    bdi_valid       : in  std_logic;
    bdi_ready       : out std_logic;
    bdi_pad_loc     : in  std_logic_vector(CCW / 8 - 1 downto 0);
    bdi_valid_bytes : in  std_logic_vector(CCW / 8 - 1 downto 0);
    bdi_size        : in  std_logic_vector(3 - 1 downto 0);
    bdi_eot         : in  std_logic;
    bdi_eoi         : in  std_logic;
    bdi_type        : in  std_logic_vector(4 - 1 downto 0);
    decrypt_in      : in  std_logic;
    hash_in         : in  std_logic;
    --!Post Processor=========================================
    bdo             : out std_logic_vector(CCW - 1 downto 0);
    bdo_valid       : out std_logic;
    bdo_ready       : in  std_logic;
    bdo_type        : out std_logic_vector(4 - 1 downto 0);
    bdo_valid_bytes : out std_logic_vector(CCW / 8 - 1 downto 0);
    end_of_block    : out std_logic;
    msg_auth_valid  : out std_logic;
    msg_auth_ready  : in  std_logic;
    msg_auth        : out std_logic
  );
end cryptocore;

architecture RTL of cryptocore is
  --============================================ Registers ==========================================================--
  signal auth_success, send_auth : std_logic;

  --============================================= Wires =============================================================--
  signal cc2_key_valid       : std_logic;
  signal cc2_key_ready       : std_logic;
  signal cc2_key_word        : std_logic_vector(CCW - 1 downto 0);
  signal cc2_key_update      : std_logic; --- ???
  signal cc2_bdi_word        : std_logic_vector(CCW - 1 downto 0);
  signal cc2_bdi_last        : std_logic;
  signal cc2_bdi_valid_bytes : std_logic_vector(CCW / 8 - 1 downto 0);
  signal cc2_bdi_eoi         : std_logic;
  signal cc2_bdi_valid       : std_logic;
  signal cc2_bdi_ready       : std_logic;
  signal cc2_bdo_word        : std_logic_vector(CCW - 1 downto 0);
  signal cc2_bdo_last        : std_logic;
  signal cc2_bdo_tagverif    : std_logic;
  signal cc2_bdo_valid_bytes : std_logic_vector(CCW / 8 - 1 downto 0);
  signal cc2_bdo_valid       : std_logic;
  signal cc2_bdo_ready       : std_logic;
  signal compare_tag         : std_logic;
  signal bdi_tagverif        : std_logic;
  signal bdo_tagverif        : std_logic;

begin
  SPARKLE_INST : entity work.sparkle
    generic map(
      IO_WIDTH         => CCW,
      SPARKLE_RATE     => 256,
      SPARKLE_CAPACITY => 128
    )
    port map(
      clk                  => clk,
      reset                => rst,
      key_bits             => cc2_key_word,
      key_valid            => cc2_key_valid,
      key_ready            => cc2_key_ready,
      key_update           => cc2_key_update,
      bdi                  => cc2_bdi_word,
      bdi_last             => cc2_bdi_last,
      bdi_validbytes            => cc2_bdi_valid_bytes,
      bdi_type               => bdi_type,
      bdi_eoi              => cc2_bdi_eoi,
      bdi_valid            => cc2_bdi_valid,
      bdi_ready            => cc2_bdi_ready,
      decrypt_op           => decrypt_in,
      hash_op              => hash_in,
      bdo_bits_word        => cc2_bdo_word,
      bdo_bits_last        => cc2_bdo_last,
      bdo_bits_valid_bytes => cc2_bdo_valid_bytes,
      bdo_bits_tag         => cc2_bdo_tagverif,
      bdo_valid            => cc2_bdo_valid,
      bdo_ready            => cc2_bdo_ready
    );

  cc2_key_word        <= reverse_bytes(key);
  cc2_key_update      <= key_update;
  cc2_key_valid       <= key_valid;
  key_ready           <= cc2_key_ready;
  cc2_bdi_word        <= reverse_bytes(bdi);
  cc2_bdi_last        <= bdi_eot;
  cc2_bdi_eoi         <= bdi_eoi;
  end_of_block        <= cc2_bdo_last;
  bdo                 <= reverse_bytes(cc2_bdo_word);
  cc2_bdi_valid_bytes <= reverse_bits(bdi_valid_bytes);
  bdo_valid_bytes     <= reverse_bits(cc2_bdo_valid_bytes);
  bdo_type            <= (others => '-');
  msg_auth_valid      <= send_auth;
  msg_auth            <= auth_success;
  --
  bdo_tagverif        <= cc2_bdo_tagverif;
  -- = HDR_TAG optimization, can't be HDR_LENGTH or HDR_HASH_VALUE (decrypt_in = 1)
  bdi_tagverif        <= decrypt_in and to_std_logic(bdi_type = HDR_TAG); -- to_std_logic(bdi_type(3 downto 2) = "10");
  cc2_bdi_valid       <= bdi_valid and not bdi_tagverif;
  cc2_bdo_ready       <= bdi_valid and bdi_tagverif when bdo_tagverif else bdo_ready;
  bdi_ready           <= bdo_tagverif and cc2_bdo_valid when bdi_tagverif else cc2_bdi_ready;
  bdo_valid           <= cc2_bdo_valid and not bdo_tagverif;
  compare_tag         <= bdo_tagverif and bdi_tagverif;

  REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        auth_success <= '1';
        send_auth    <= '0';
      else
        if msg_auth_valid and msg_auth_ready then
          auth_success <= '1';
          send_auth    <= '0';
        elsif compare_tag and bdi_valid and bdi_ready then
          if bdo /= bdi then
            auth_success <= '0';
          end if;
          if cc2_bdo_last = '1' then
            send_auth <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
