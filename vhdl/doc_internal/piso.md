# Entity: PISO 

- **File**: piso.vhdl
## Diagram

![Diagram](piso.svg "Diagram")
## Generics

| Generic name     | Type     | Value | Description |
| ---------------- | -------- | ----- | ----------- |
| WORD_WIDTH       | positive |       |             |
| NUM_WORDS        | positive |       |             |
| WITH_VALID_BYTES | boolean  |       |             |
## Ports

| Port name            | Direction | Type                                                         | Description |
| -------------------- | --------- | ------------------------------------------------------------ | ----------- |
| clk                  | in        | std_logic                                                    |             |
| reset                | in        | std_logic                                                    |             |
| in_bits_block        | in        | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0)     |             |
| in_bits_valid_words  | in        | t_bit_array(0 to NUM_WORDS - 1)                              |             |
| in_bits_valid_bytes  | in        | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0) |             |
| in_bits_last         | in        | std_logic                                                    |             |
| in_valid             | in        | std_logic                                                    |             |
| in_ready             | out       | std_logic                                                    |             |
| out_bits_word        | out       | std_logic_vector(WORD_WIDTH - 1 downto 0)                    |             |
| out_bits_last        | out       | std_logic                                                    |             |
| out_bits_valid_bytes | out       | std_logic_vector(WORD_WIDTH / 8 - 1 downto 0)                |             |
| out_valid            | out       | std_logic                                                    |             |
| out_ready            | in        | std_logic                                                    |             |
## Signals

| Name          | Type                                                         | Description |
| ------------- | ------------------------------------------------------------ | ----------- |
| data_block    | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH - 1 downto 0)     |             |
| validwords    | t_bit_array(0 to NUM_WORDS - 1)                              |             |
| validbytes    | t_slv_array(0 to NUM_WORDS - 1)(WORD_WIDTH / 8 - 1 downto 0) |             |
| last_block    | std_logic                                                    |             |
| do_enq        | boolean                                                      |             |
| do_deq        | boolean                                                      |             |
| empty         | boolean                                                      |             |
| last_or_empty | boolean                                                      |             |
## Processes
- VALIDWORDS_PROC: ( clk )
- DATABLOCK_PROC: ( clk )
