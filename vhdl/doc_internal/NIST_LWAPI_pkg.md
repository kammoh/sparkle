# Package: NIST_LWAPI_pkg 

- **File**: NIST_LWAPI_pkg.vhd
## Constants

| Name       | Type     | Value                 | Description                                                                                                                                                                                                                                                                                                                                                    |
| ---------- | -------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| W          | natural  | LWC_config.W          | **** DO NOT CHANGE ANY OF THE CONSTANT VALUES HERE! *****  to set design-specific values for these parameters, create LWC_config package file  Please see 'LWC_config_template.vhd' for a functional template.  Also examples for different LWC_config files are provided in the dummy_lwc directory<br>  External bus: supported values are 8, 16 and 32 bits |
| SW         | natural  | LWC_config.SW         | currently only W=SW is supported                                                                                                                                                                                                                                                                                                                               |
| PDI_SHARES | positive | LWC_config.PDI_SHARES | Applicable only to protected implementations  For unprotected implementations they are set to the default values of       PDI_SHARES=SDI_SHARES=1, RW=0                                                                                                                                                                                                        |
| SDI_SHARES | positive | LWC_config.SDI_SHARES |                                                                                                                                                                                                                                                                                                                                                                |
| RW         | natural  | LWC_config.RW         |                                                                                                                                                                                                                                                                                                                                                                |
| ASYNC_RSTN | boolean  | LWC_config.ASYNC_RSTN | Asynchronous and active-low reset.                                                                                                                                                                                                                                                                                                                             |
## Functions
- clear_invalid_bytes <font id="function_arguments">(bdo_data,<br><span style="padding-left:20px"> bdo_valid_bytes : std_logic_vector) </font> <font id="function_return">return std_logic_vector </font>
  - **Description**
  clears invalid bytes from bdo_data

- log2ceil <font id="function_arguments">(n : natural) </font> <font id="function_return">return natural </font>
  - **Description**
  Returns the number of bits required to represet positive integers strictly less than `n` (0 to n - 1 inclusive)
 Output is equal to ceil(log2(n))
 log2ceil(0) -> 0

- to_std_logic <font id="function_arguments">(a : boolean) </font> <font id="function_return">return std_logic </font>
  - **Description**
  convert boolean to std_logic

- TO_INT01 <font id="function_arguments">(S : UNSIGNED) </font> <font id="function_return">return INTEGER </font>
  - **Description**
  first TO_01 and then TO_INTEGER

- TO_INT01 <font id="function_arguments">(S : std_logic_vector) </font> <font id="function_return">return INTEGER </font>
- is_zero <font id="function_arguments">(slv : std_logic_vector) </font> <font id="function_return">return boolean </font>
  - **Description**
  check if all bits are zero

- is_zero <font id="function_arguments">(u : unsigned) </font> <font id="function_return">return boolean </font>
- reverse_bits <font id="function_arguments">(slv : std_logic_vector) </font> <font id="function_return">return std_logic_vector </font>
  - **Description**
  Reverse the Bit order of the input vector.

- reverse_bits <font id="function_arguments">(u : unsigned) </font> <font id="function_return">return unsigned </font>
- reverse_bytes <font id="function_arguments">(vec : std_logic_vector) </font> <font id="function_return">return std_logic_vector </font>
  - **Description**
  reverse byte endian-ness of the input vector

- to_1H <font id="function_arguments">(u : unsigned) </font> <font id="function_return">return unsigned </font>
  - **Description**
  binary to one-hot encoder

- to_1H <font id="function_arguments">(slv : std_logic_vector) </font> <font id="function_return">return std_logic_vector </font>
- to_1H <font id="function_arguments">(u : unsigned;<br><span style="padding-left:20px"> out_bits : positive) </font> <font id="function_return">return unsigned </font>
- to_1H <font id="function_arguments">(slv : std_logic_vector;<br><span style="padding-left:20px"> out_bits : positive) </font> <font id="function_return">return std_logic_vector </font>
- barrel_shift_left <font id="function_arguments">(u : unsigned;<br><span style="padding-left:20px"> sh : unsigned) </font> <font id="function_return">return unsigned </font>
  - **Description**
  dynamic (u << sh) using an efficient barrel shifter

- minimum <font id="function_arguments">(a,<br><span style="padding-left:20px"> b : integer) </font> <font id="function_return">return integer </font>
- maximum <font id="function_arguments">(a,<br><span style="padding-left:20px"> b : integer) </font> <font id="function_return">return integer </font>
- lwc_hread <font id="function_arguments">(l : inout line;<br><span style="padding-left:20px"> value : out std_logic_vector;<br><span style="padding-left:20px"> good : out boolean) </font> <font id="function_return">return ()</font>
- lwc_or_reduce <font id="function_arguments">(l : std_logic_vector) </font> <font id="function_return">return std_logic </font>
- lwc_and_reduce <font id="function_arguments">(l : std_logic_vector) </font> <font id="function_return">return std_logic </font>
- lwc_or_reduce <font id="function_arguments">(u : unsigned) </font> <font id="function_return">return std_logic </font>
- lwc_and_reduce <font id="function_arguments">(u : unsigned) </font> <font id="function_return">return std_logic </font>
- lwc_to_hstring <font id="function_arguments">(value : std_logic_vector) </font> <font id="function_return">return string </font>
- high_bits <font id="function_arguments">(slv : std_logic_vector;<br><span style="padding-left:20px"> n : integer) </font> <font id="function_return">return std_logic_vector </font>
  - **Description**
  return n most significant bits of slv

