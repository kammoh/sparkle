library IEEE;
use IEEE.std_logic_1164.all;

package design_pkg is
  constant CCSW            : integer := 32;  --! key width
  constant CCW             : integer := 32;  --! bdo/bdi width
  constant TAG_SIZE        : integer := 128; --! Tag size
  constant HASH_VALUE_SIZE : integer := 256; --! Hash value size
end design_pkg;
