# Entity: SIPO 

- **File**: sipo.vhdl
## Diagram

![Diagram](sipo.svg "Diagram")
## Generics

| Generic name     | Type                 | Value           | Description |
| ---------------- | -------------------- | --------------- | ----------- |
| WORD_WIDTH       | positive             | 32              |             |
| NUM_WORDS        | positive             | 8               |             |
| WITH_VALID_BYTES | boolean              | FALSE           |             |
| ZERO_FILL        | boolean              | FALSE           |             |
| PADDING_BYTE     | unsigned(7 downto 0) | (others => '0') |             |
| PIPELINED        | boolean              | TRUE            |             |
## Ports

| Port name            | Direction | Type                                                         | Description |
| -------------------- | --------- | ------------------------------------------------------------ | ----------- |
| clk                  | in        | std_logic                                                    |             |
| reset                | in        | std_logic                                                    |             |
| in_bits_word         | in        | std_logic_vector(WORD_WIDTH - 1 downto 0)                    |             |
| in_bits_last         | in        | std_logic                                                    |             |
| in_bits_valid_bytes  | in        | std_logic_vector(WORD_WIDTH / 8 - 1 downto 0)                |             |
| in_valid             | in        | std_logic                                                    |             |
| in_ready             | out       | std_logic                                                    |             |
| out_bits_block       | out       | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0)     |             |
| out_bits_valid_words | out       | t_bit_array(0 to NUM_WORDS - 1)                              |             |
| out_bits_bva         | out       | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0) |             |
| out_bits_last        | out       | std_logic                                                    |             |
| out_bits_incomp      | out       | std_logic                                                    |             |
| out_valid            | out       | std_logic                                                    |             |
| out_ready            | in        | std_logic                                                    |             |
## Signals

| Name            | Type                                                         | Description |
| --------------- | ------------------------------------------------------------ | ----------- |
| block_reg       | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0)     |             |
| validbytes      | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0) |             |
| word_valids     | t_bit_array(0 to NUM_WORDS - 1)                              |             |
| fill_zeros      | boolean                                                      |             |
| last            | std_logic                                                    |             |
| do_pad_byte     | boolean                                                      |             |
| incomplete      | boolean                                                      |             |
| do_enq          | boolean                                                      |             |
| do_deq          | boolean                                                      |             |
| do_shiftin      | boolean                                                      |             |
| full            | boolean                                                      |             |
| one_short       | boolean                                                      |             |
| next_word       | std_logic_vector(WORD_WIDTH - 1 downto 0)                    |             |
| next_validbytes | std_logic_vector(WORD_WIDTH / 8 - 1 downto 0)                |             |
## Processes
- COMB_PROC: ( all )
- unnamed: ( clk )
