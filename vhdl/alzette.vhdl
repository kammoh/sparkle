library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package alzette_defs is
    subtype t_uint32 is unsigned(31 downto 0);
    type rcon_t is array (0 to 7) of t_uint32;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alzette_defs.all;

entity alzette is
    generic(G_I : natural := 0);
    port(
        clk  : in  std_logic;
        rst  : in  std_logic;
        xin  : in  t_uint32;
        yin  : in  t_uint32;
        xout : out t_uint32;
        yout : out t_uint32
    );
end entity alzette;

architecture RTL of alzette is

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
    constant RCON : rcon_t := (
        X"B7E15162", X"BF715880", X"38B4DA56", X"324E7738",
        X"BB1185EB", X"4F7C7B57", X"CFBFA1C8", X"C2B3293D"
    );

begin

    process(clk)
        variable x1, y1 : t_uint32;
    begin
        if rising_edge(clk) then
            x1   := xin;
            y1   := yin;
            alzette(RCON(G_I), x1, y1);
            xout <= x1;
            yout <= y1;
        end if;
    end process;

end architecture;
