library IEEE;
use IEEE.std_logic_1164.all;

package design_pkg is
  constant CCSW : integer;
  constant CCW  : integer;

  constant TAG_SIZE        : integer;   --! Tag size
  constant HASH_VALUE_SIZE : integer;   --! Hash value size
  constant CCWdiv8         : integer;   --! derived from parameters above, assigned in body.

  --! Calculate log2 and round up.
  function reverse_byte(vec : std_logic_vector) return std_logic_vector;
  --! Reverse the Bit order of the input vector.
  function reverse_bit(vec : std_logic_vector) return std_logic_vector;
end design_pkg;

package body design_pkg is

  --! design parameters needed by the PreProcessor, PostProcessor, and LWC
  constant CCSW            : integer := 32; --! key width
  constant CCW             : integer := 32; --! bdo/bdi width
  constant TAG_SIZE        : integer := 128; --! Tag size
  constant HASH_VALUE_SIZE : integer := 256; --! Hash value size
  constant CCWdiv8         : integer := CCW / 8; -- derived from parameters above

  --! Reverse the Byte order of the input word.
  function reverse_byte(vec : std_logic_vector) return std_logic_vector is
    variable res     : std_logic_vector(vec'length - 1 downto 0);
    constant n_bytes : integer := vec'length / 8;
  begin
    -- Check that vector length is actually byte aligned.
    assert (vec'length mod 8 = 0)
    report "Vector size must be in multiple of Bytes!" severity failure;

    -- Loop over every byte of vec and reorder it in res.
    for i in 0 to (n_bytes - 1) loop
      res(8 * (i + 1) - 1 downto 8 * i) := vec(8 * (n_bytes - i) - 1 downto 8 * (n_bytes - i - 1));
    end loop;

    return res;
  end function reverse_byte;

  --! Reverse the Bit order of the input vector.
  function reverse_bit(vec : std_logic_vector) return std_logic_vector is
    variable res : std_logic_vector(vec'length - 1 downto 0);
  begin
    for i in 0 to (vec'length - 1) loop
      res(i) := vec(vec'length - i - 1);
    end loop;
    return res;
  end function reverse_bit;
end package body design_pkg;
