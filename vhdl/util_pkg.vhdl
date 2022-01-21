--===================================================================================================================--
-- Author:         Kamyar Mohajerani
-- VHDL Standard:  2008
-- Description:   
--===================================================================================================================--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

package util_pkg is
  --=================================================================================================================--
  subtype t_uint32 is unsigned(31 downto 0);
  type t_uint32_array is array (natural range <>) of t_uint32;
  type t_bit_array is array (natural range <>) of std_logic;
  type t_slv_array is array (natural range <>) of std_logic_vector;
  type t_unsigned_array is array (natural range <>) of unsigned;

  --=================================================================================================================--
  --
  function to_uint32_array(a : t_slv_array) return t_uint32_array;
  --
  -- convert uint32_array_t to std_logic_vector(31 downto 0)
  function to_slva(a : t_uint32_array) return t_slv_array;
  --
end package;

package body util_pkg is
  function to_uint32_array(a : t_slv_array) return t_uint32_array is
    variable ret : t_uint32_array(a'range);
  begin
    for i in a'range loop
      ret(i) := unsigned(a(i));
    end loop;
    return ret;
  end function;

  function to_slva(a : t_uint32_array) return t_slv_array is
    constant el  : unsigned := a(a'left);
    variable ret : t_slv_array(a'range)(el'range);
  begin
    for i in a'range loop
      ret(i) := std_logic_vector(a(i));
    end loop;
    return ret;
  end function;

end package body;
