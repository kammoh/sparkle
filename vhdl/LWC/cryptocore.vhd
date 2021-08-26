library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- use work.NIST_LWAPI_pkg.all;
use work.design_pkg.all;
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
  signal auth_success, send_auth : boolean;

  --============================================= Wires =============================================================--

  signal sparkle_key_valid            : std_logic;
  signal sparkle_key_ready            : std_logic;
  signal sparkle_key_bits_word        : std_logic_vector(CCW - 1 downto 0);
  signal sparkle_key_update           : std_logic; --- ???
  signal sparkle_bdi_bits_word        : std_logic_vector(CCW - 1 downto 0);
  signal sparkle_bdi_bits_last        : std_logic;
  signal sparkle_bdi_bits_valid_bytes : std_logic_vector(CCW / 8 - 1 downto 0);
  signal sparkle_bdi_bits_ad          : std_logic;
  signal sparkle_bdi_bits_ct          : std_logic;
  signal sparkle_bdi_bits_hm          : std_logic;
  signal sparkle_bdi_bits_eoi         : std_logic;
  signal sparkle_bdi_valid            : std_logic;
  signal sparkle_bdi_ready            : std_logic;
  signal sparkle_bdo_bits_word        : std_logic_vector(CCW - 1 downto 0);
  signal sparkle_bdo_bits_last        : std_logic;
  signal sparkle_bdo_bits_tag         : std_logic;
  signal sparkle_bdo_bits_valid_bytes : std_logic_vector(CCW / 8 - 1 downto 0);
  signal sparkle_bdo_valid            : std_logic;
  signal sparkle_bdo_ready            : std_logic;
  signal verify_tag                   : boolean;

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
      key_bits             => sparkle_key_bits_word,
      key_valid            => sparkle_key_valid,
      key_ready            => sparkle_key_ready,
      key_update           => sparkle_key_update,
      bdi_bits_word        => sparkle_bdi_bits_word,
      bdi_bits_last        => sparkle_bdi_bits_last,
      bdi_bits_valid_bytes => sparkle_bdi_bits_valid_bytes,
      bdi_bits_ad          => sparkle_bdi_bits_ad,
      bdi_bits_ct          => sparkle_bdi_bits_ct,
      bdi_bits_hm          => sparkle_bdi_bits_hm,
      bdi_bits_eoi         => sparkle_bdi_bits_eoi,
      bdi_valid            => sparkle_bdi_valid,
      bdi_ready            => sparkle_bdi_ready,
      bdo_bits_word        => sparkle_bdo_bits_word,
      bdo_bits_last        => sparkle_bdo_bits_last,
      bdo_bits_valid_bytes => sparkle_bdo_bits_valid_bytes,
      bdo_bits_tag         => sparkle_bdo_bits_tag,
      bdo_valid            => sparkle_bdo_valid,
      bdo_ready            => sparkle_bdo_ready
    );

  COMB_PROC : process(all)
  begin
    sparkle_key_valid            <= key_valid;
    key_ready                    <= sparkle_key_ready;
    sparkle_key_update           <= key_update;
    sparkle_bdi_bits_last        <= bdi_eot;
    sparkle_bdi_bits_ad          <= '1' when bdi_type(3 downto 2) = "00" else '0';
    sparkle_bdi_bits_ct          <= decrypt_in and not sparkle_bdi_bits_ad;
    sparkle_bdi_bits_hm          <= hash_in;
    sparkle_bdi_bits_eoi         <= bdi_eoi;
    sparkle_bdi_valid            <= bdi_valid;
    bdi_ready                    <= sparkle_bdi_ready;
    end_of_block                 <= sparkle_bdo_bits_last;
    bdo_valid                    <= sparkle_bdo_valid;
    sparkle_bdo_ready            <= bdo_ready;
    sparkle_key_bits_word        <= reverse_byte(key);
    sparkle_bdi_bits_word        <= reverse_byte(bdi);
    bdo                          <= reverse_byte(sparkle_bdo_bits_word);
    bdo_valid_bytes              <= reverse_bit(sparkle_bdo_bits_valid_bytes);
    sparkle_bdi_bits_valid_bytes <= reverse_bit(bdi_valid_bytes);
    bdo_type                     <= (others => '-');
    msg_auth_valid               <= '1' when send_auth else '0';
    msg_auth                     <= '1' when auth_success else '0';
    verify_tag                   <= not send_auth and decrypt_in = '1' and sparkle_bdo_bits_tag = '1';

    if decrypt_in = '1' and bdi_type(3 downto 2) = "10" then -- TAG verif
      bdi_ready         <= sparkle_bdo_valid when verify_tag else '0';
      sparkle_bdi_valid <= '0';
    end if;

    if verify_tag then
      sparkle_bdo_ready <= bdi_valid;
      bdo_valid         <= '0';
    end if;

  end process;

  REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        auth_success <= TRUE;
        send_auth    <= FALSE;
      else
        if verify_tag then
          if sparkle_bdo_valid = '1' and sparkle_bdo_ready = '1' then
            if bdo /= bdi then
              auth_success <= FALSE;
            end if;
            if sparkle_bdo_bits_last = '1' then
              send_auth <= TRUE;
            end if;
          end if;
        end if;
        if msg_auth_valid = '1' and msg_auth_ready = '1' then
          auth_success <= TRUE;
          send_auth    <= FALSE;
        end if;
      end if;
    end if;
  end process;

end architecture;
