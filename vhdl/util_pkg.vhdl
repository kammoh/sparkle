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
  subtype uint32_t is unsigned(31 downto 0);
  type uint32_array_t is array (natural range <>) of uint32_t;
  type bit_array_t is array (natural range <>) of std_logic;
  type slv_array_t is array (natural range <>) of std_logic_vector;
  type unsigned_array_t is array (natural range <>) of unsigned;

  --=================================================================================================================--
  --
  function log2ceil(n : positive) return natural;
  --
  function to_uint32_array(a : slv_array_t) return uint32_array_t;
  --
  -- convert uint32_array_t to std_logic_vector(31 downto 0)
  function to_slva(a : uint32_array_t) return slv_array_t;
  --
  -- convert boolean to std_logic
  function to_sl(a : boolean) return std_logic;
end package;

package body util_pkg is
  function log2ceil(n : positive) return natural is
    variable pow2 : positive := 1;
    variable r    : natural  := 0;
  begin
    while n > pow2 loop
      pow2 := pow2 * 2;
      r    := r + 1;
    end loop;
    return r;
  end function;

  function to_uint32_array(a : slv_array_t) return uint32_array_t is
    variable ret : uint32_array_t(a'range);
  begin
    for i in a'range loop
      ret(i) := unsigned(a(i));
    end loop;
    return ret;
  end function;

  function to_slva(a : uint32_array_t) return slv_array_t is
    constant el  : unsigned := a(a'left);
    variable ret : slv_array_t(a'range)(el'range);
  begin
    for i in a'range loop
      ret(i) := std_logic_vector(a(i));
    end loop;
    return ret;
  end function;

  function to_sl(a : boolean) return std_logic is
  begin
    if a then
      return '1';
    else
      return '0';
    end if;
  end function;
end package body;
