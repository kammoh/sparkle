# Package: util_pkg 

- **File**: util_pkg.vhdl
## Types

| Name             | Type                                         | Description |
| ---------------- | -------------------------------------------- | ----------- |
| t_uint32_array   | array (natural range <>) of t_uint32         |             |
| t_bit_array      | array (natural range <>) of std_logic        |             |
| t_slv_array      | array (natural range <>) of std_logic_vector |             |
| t_unsigned_array | array (natural range <>) of unsigned         |             |
## Functions
- to_uint32_array <font id="function_arguments">(a : t_slv_array) </font> <font id="function_return">return t_uint32_array </font>
- to_slva <font id="function_arguments">(a : t_uint32_array) </font> <font id="function_return">return t_slv_array </font>
