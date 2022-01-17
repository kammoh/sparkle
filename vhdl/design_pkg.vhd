library IEEE;
use IEEE.std_logic_1164.all;

package design_pkg is
  constant CCSW : integer;
  constant CCW  : integer;

  constant TAG_SIZE        : integer;   --! Tag size
  constant HASH_VALUE_SIZE : integer;   --! Hash value size
  constant CCWdiv8         : integer;   --! derived from parameters above, assigned in body.

end design_pkg;

package body design_pkg is

  --! design parameters needed by the PreProcessor, PostProcessor, and LWC
  constant CCSW            : integer := 32; --! key width
  constant CCW             : integer := 32; --! bdo/bdi width
  constant TAG_SIZE        : integer := 128; --! Tag size
  constant HASH_VALUE_SIZE : integer := 256; --! Hash value size
  constant CCWdiv8         : integer := CCW / 8; -- derived from parameters above

end package body design_pkg;
