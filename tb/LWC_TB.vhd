--===============================================================================================--
--! @file       LWC_TB.vhd
--! @brief      NIST Lightweight Cryptography Testbench
--! @project    GMU LWC Package
--! @author     Ekawat (ice) Homsirikamol
--! @author     Kamyar Mohajerani
--! @copyright  Copyright (c) 2015, 2020, 2021, 2022 Cryptographic Engineering Research Group
--!             ECE Department, George Mason University Fairfax, VA, U.S.A.
--!             All rights Reserved.
--! @version    1.2.0
--! @license    This project is released under the GNU Public License.
--!             The license and distribution terms for this file may be
--!             found in the file LICENSE in this distribution or at
--!             http://www.gnu.org/licenses/gpl-3.0.txt
--! @note       This is publicly available encryption source code that falls
--!             under the License Exception TSU (Technology and software-
--!             unrestricted)
--===============================================================================================--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.NIST_LWAPI_pkg.all;
use work.LWC_pkg.all;

entity LWC_TB IS
    generic(
        G_MAX_FAILURES     : integer := 0; --! Maximum number of failures before stopping the simulation
        G_TEST_MODE        : integer := 0; --! 0: normal, 1: stall both sdi/pdi_valid and do_ready, 2: stall sdi/pdi_valid, 3: stall do_ready, 4: Timing (cycle) measurement 
        G_TEST_IPSTALL     : integer := 3; --! Number of cycles to stall pdi_valid
        G_TEST_ISSTALL     : integer := 3; --! Number of cycles to stall sdi_valid
        G_TEST_OSTALL      : integer := 3; --! Number of cycles to stall do_ready
        G_PERIOD_PS        : integer := 10_000; --! Simulation clock period in picoseconds
        G_FNAME_PDI        : string  := "../KAT/v1/pdi.txt"; --! Path to the input file containing cryptotvgen PDI testvector data
        G_FNAME_SDI        : string  := "../KAT/v1/sdi.txt"; --! Path to the input file containing cryptotvgen SDI testvector data
        G_FNAME_RDI        : string  := "../KAT/v1/rdi.txt"; --! Path to the input file containing random data
        G_FNAME_DO         : string  := "../KAT/v1/do.txt"; --! Path to the input file containing cryptotvgen DO testvector data
        G_FNAME_LOG        : string  := "log.txt"; --! Path to the generated log file
        G_FNAME_TIMING     : string  := "timing.txt"; --! Path to the generated timing measurements (when G_TEST_MODE=4)
        G_FNAME_FAILED_TVS : string  := "failed_testvectors.txt"; --! Path to the generated log of failed testvector words
        G_FNAME_RESULT     : string  := "result.txt"; --! Path to the generated result file containing 0 or 1  -- REDUNDANT / NOT USED
        G_PRERESET_WAIT_NS : integer := 0; --! Time (in nanosecods) to wait before reseting UUT. Xilinx GSR takes 100ns, required for post-synth simulation
        G_INPUT_DELAY_NS   : integer := 0 --! Input delay
    );
end LWC_TB;

architecture TB of LWC_TB is
    --================================================== Constants ==================================================--
    constant W_S         : positive       := W * PDI_SHARES;
    constant SW_S        : positive       := SW * SDI_SHARES;
    constant input_delay : TIME           := G_INPUT_DELAY_NS * ns;
    constant clk_period  : TIME           := G_PERIOD_PS * ps;
    constant TB_HEAD     : string(1 to 6) := "# TB :";
    -- can be placed in the middle of a file
    constant EOF_HEAD    : string(1 to 6) := "###EOF";
    constant INS_HEAD    : string(1 to 6) := "INS = ";
    constant HDR_HEAD    : string(1 to 6) := "HDR = ";
    constant DAT_HEAD    : string(1 to 6) := "DAT = ";
    constant STT_HEAD    : string(1 to 6) := "STT = ";

    constant TESTMODE_NORMAL : integer := 0;
    constant TESTMODE_TIMING : integer := 4;

    --=================================================== Signals ===================================================--
    --! stop clock generation
    signal stop_clock          : boolean                             := False;
    --! initial reset of UUT is complete
    signal reset_done          : boolean                             := False;
    --=================================================== Wirings ===================================================--
    signal clk                 : std_logic                           := '0';
    signal rst                 : std_logic                           := '0';
    --! PDI
    signal pdi_data            : std_logic_vector(W_S - 1 downto 0)  := (others => '0');
    signal pdi_data_delayed    : std_logic_vector(W_S - 1 downto 0)  := (others => '0');
    signal pdi_valid           : std_logic                           := '0';
    signal pdi_valid_delayed   : std_logic                           := '0';
    signal pdi_ready           : std_logic;
    --! SDI
    signal sdi_data            : std_logic_vector(SW_S - 1 downto 0) := (others => '0');
    signal sdi_data_delayed    : std_logic_vector(SW_S - 1 downto 0) := (others => '0');
    signal sdi_valid           : std_logic                           := '0';
    signal sdi_valid_delayed   : std_logic                           := '0';
    signal sdi_ready           : std_logic;
    --! DO
    signal do_data             : std_logic_vector(W_S - 1 downto 0);
    signal do_valid            : std_logic;
    signal do_last             : std_logic;
    signal do_ready            : std_logic                           := '0';
    signal do_ready_delayed    : std_logic                           := '0';
    -- Used only for protected implementations:
    --   RDI
    signal rdi_data            : std_logic_vector(RW - 1 downto 0)   := (others => '0');
    signal rdi_data_delayed    : std_logic_vector(RW - 1 downto 0)   := (others => '0');
    signal rdi_valid           : std_logic                           := '0';
    signal rdi_valid_delayed   : std_logic                           := '0';
    signal rdi_ready           : std_logic;
    --   unshared version of DO
    signal do_sum              : std_logic_vector(W - 1 downto 0);
    -- Counters
    signal pdi_operation_count : integer                             := 0;
    signal cycle_counter       : natural                             := 0;
    signal num_rand_vectors    : natural                             := 0;
    --
    signal start_cycle         : natural;
    signal timing_started      : boolean                             := False;
    signal timing_stopped      : boolean                             := False;

    --================================================== I/O files ==================================================--
    -- cryptotvgen KAT files
    file pdi_file      : TEXT open READ_MODE is G_FNAME_PDI; -- always required
    file sdi_file      : TEXT;
    file do_file       : TEXT open READ_MODE is G_FNAME_DO; -- always required
    file rdi_file      : TEXT;
    -- output files
    file log_file      : TEXT open write_mode is G_FNAME_LOG;
    file timing_file   : TEXT;
    file result_file   : TEXT open write_mode is G_FNAME_RESULT;
    file failures_file : TEXT open write_mode is G_FNAME_FAILED_TVS;

    --================================================== functions ==================================================--
    -- compare received word against expected word
    -- returns true if they match or if the unmatched bit was a don't-care
    function word_pass(actual, expected : std_logic_vector) return boolean is
    begin
        for i in expected'range loop
            if actual(i) /= expected(i) and expected(i) /= 'X' and expected(i) /= '-' then
                return False;
            end if;
        end loop;
        return True;
    end function;

    -- sum up all shares. Returns do_data if num_shares=1)
    function xor_shares(slv : std_logic_vector; num_shares : positive) return std_logic_vector is
        constant share_width : natural                                    := slv'length / num_shares;
        variable ret         : std_logic_vector(share_width - 1 downto 0) := slv(share_width - 1 downto 0);
    begin
        for i in 1 to num_shares - 1 loop
            ret := ret xor slv((i + 1) * share_width - 1 downto i * share_width);
        end loop;
        return ret;
    end function;

    -- TODO re-implement random stalls
    impure function get_stalls(max_stalls : integer) return integer is
    begin
        return max_stalls;
    end function;

begin
    --===========================================================================================--
    -- generate clock
    clockProProc : process
    begin
        if not stop_clock then
            clk <= '1';
            wait for clk_period / 2;
            clk <= '0';
            wait for clk_period / 2;
        else
            wait;
        end if;
    end process;

    -- generate reset
    resetProc : process
    begin
        report LF & " -- Testvectors:  " & G_FNAME_PDI & " " & G_FNAME_SDI & " " & G_FNAME_DO & LF &
        " -- Clock Period: " & integer'image(G_PERIOD_PS) & " ps" & LF &
        " -- Test Mode:    " & integer'image(G_TEST_MODE) & LF &
        " -- Max Failures: " & integer'image(G_MAX_FAILURES) & LF & CR severity note;

        wait for G_PRERESET_WAIT_NS * ns;
        if ASYNC_RSTN then
            rst <= '0';
            wait for 2 * clk_period;
            rst <= '1';
        else
            rst <= '1';
            wait for 2 * clk_period + input_delay;
            rst <= '0';
        end if;
        wait until rising_edge(clk);
        wait for clk_period;            -- optional
        reset_done <= True;
        wait;
    end process;

    cycleCountProc : process(clk)
    begin
        if reset_done and rising_edge(clk) then
            cycle_counter <= cycle_counter + 1;
        end if;
    end process;

    --===========================================================================================--
    -- LWC is instantiated as a component for mixed languages simulation
    uut : LWC
        port map(
            clk       => clk,
            rst       => rst,
            pdi_data  => pdi_data_delayed,
            pdi_valid => pdi_valid_delayed,
            pdi_ready => pdi_ready,
            sdi_data  => sdi_data_delayed,
            sdi_valid => sdi_valid_delayed,
            sdi_ready => sdi_ready,
            do_data   => do_data,
            do_last   => do_last,
            do_valid  => do_valid,
            do_ready  => do_ready_delayed
            -- LWC_SCA:
            -- , rdi_data  => rdi_data_delayed,
            -- rdi_valid => rdi_valid_delayed,
            -- rdi_ready => rdi_ready
        );

    --===========================================================================================--

    pdi_data_delayed  <= transport pdi_data after input_delay;
    pdi_valid_delayed <= transport pdi_valid after input_delay;
    sdi_data_delayed  <= transport sdi_data after input_delay;
    sdi_valid_delayed <= transport sdi_valid after input_delay;
    do_ready_delayed  <= transport do_ready after input_delay;

    do_sum <= xor_shares(do_data, PDI_SHARES);

    GEN_RDI : if RW > 0 generate
    begin
        rdi_data_delayed  <= transport rdi_data after input_delay;
        rdi_valid_delayed <= transport rdi_valid after input_delay;
        rdi_proc : process
            variable rdi_line : line;
            variable rdi_vec  : std_logic_vector(RW - 1 downto 0);
            variable read_ok  : boolean;
        begin
            report LF & "RW=" & integer'image(RW);
            wait until reset_done and rising_edge(clk);
            if G_FNAME_RDI'length < 1 then
                rdi_data  <= (others => '1');
                rdi_valid <= '1';
            else
                file_open(rdi_file, G_FNAME_RDI, READ_MODE);
                loop
                    loop
                        if endfile(rdi_file) then
                            assert num_rand_vectors > 0 report "RDI file is empty!" severity failure;
                            -- report "Reached end of " & G_FNAME_RDI & ", reading from the begining.";
                            -- re-read from the biginging
                            file_close(rdi_file);
                            file_open(rdi_file, G_FNAME_RDI, READ_MODE);
                        end if;
                        readline(rdi_file, rdi_line);
                        if rdi_line'length > 0 then
                            exit;
                        end if;
                    end loop;
                    if rdi_line'length * 4 < RW then
                        report "Error: RDI line is shorter than RW " severity failure;
                        exit;           -- exit the loop
                    end if;
                    lwc_hread(rdi_line, rdi_vec, read_ok);
                    if not read_ok then
                        report "Error while reading " & G_FNAME_RDI severity failure;
                        exit;           -- exit the loop
                    end if;
                    rdi_data         <= rdi_vec;
                    rdi_valid        <= '1';
                    wait until rising_edge(clk) and rdi_ready = '1' and rdi_valid_delayed = '1';
                    num_rand_vectors <= num_rand_vectors + 1;
                    rdi_valid        <= '0';
                end loop;
                file_close(rdi_file);
            end if;
            wait;                       -- until simulation ends
        end process;
    end generate;

    --===========================================================================================--
    --====================================== PDI Stimulus =======================================--
    tb_read_pdi : process
        variable line_data    : LINE;
        variable word_block   : std_logic_vector(W_S - 1 downto 0) := (others => '0');
        variable read_ok      : boolean;
        variable line_head    : string(1 to 6);
        variable stall_cycles : integer;
        variable actkey_ins   : boolean;
        variable hash_ins     : boolean;
        -- instruction other than actkey or hash was already sent
        variable op_sent      : boolean                            := False;
    begin
        -- wait for the clock edge after reset is complete
        wait until reset_done;
        wait until rising_edge(clk);
        --
        while not endfile(pdi_file) loop
            readline(pdi_file, line_data);
            read(line_data, line_head, read_ok); --! read line header
            if read_ok and (line_head = INS_HEAD) then
                pdi_operation_count <= pdi_operation_count + 1;
            end if;
            if read_ok and (line_head = INS_HEAD or line_head = HDR_HEAD or line_head = DAT_HEAD) then
                loop
                    lwc_hread(line_data, word_block, read_ok);
                    if not read_ok then
                        exit;
                    end if;
                    actkey_ins := (line_head = INS_HEAD) and (word_block(W - 1 downto W - 4) = INST_ACTKEY);
                    hash_ins   := (line_head = INS_HEAD) and (word_block(W - 1 downto W - 4) = INST_HASH);
                    -- stalls
                    if G_TEST_MODE = 1 or G_TEST_MODE = 2 then
                        stall_cycles := get_stalls(G_TEST_IPSTALL);
                        if stall_cycles > 0 then
                            pdi_valid <= '0';
                            wait for stall_cycles * clk_period;
                            wait until rising_edge(clk); -- TODO verify number of generated stall cycles
                        end if;
                    elsif G_TEST_MODE = TESTMODE_TIMING and line_head = INS_HEAD and (actkey_ins or hash_ins or op_sent) and timing_started then
                        if not timing_stopped then
                            pdi_valid <= '0';
                            wait until rising_edge(clk) and timing_stopped; -- wait for tb_verify_do process to complete timed operation
                        end if;
                        timing_started <= False; -- Ack receiving timing_stopped = '1' to tb_verify_do process
                    end if;

                    pdi_valid <= '1';
                    pdi_data  <= word_block;
                    wait until rising_edge(clk) and pdi_ready = '1';
                    -- NOTE: should never stall here
                    if G_TEST_MODE = TESTMODE_TIMING and line_head = INS_HEAD then
                        op_sent := not actkey_ins and not hash_ins;
                        if not timing_started then
                            start_cycle    <= cycle_counter;
                            timing_started <= True;
                            wait for 0 ns; -- yield to update timing_started signal as there could be no wait before next read
                        end if;
                    end if;
                end loop;
            end if;
        end loop;
        --
        pdi_valid <= '0';
        if timing_started and not timing_stopped then
            wait until timing_stopped;
            timing_started <= False;
        end if;
        wait;                           -- until simulation ends
    end process;

    --===========================================================================================--
    --====================================== SDI Stimulus =======================================--
    tb_read_sdi : process
        variable line_data    : LINE;
        variable word_block   : std_logic_vector(SW_S - 1 downto 0);
        variable read_ok      : boolean;
        variable line_head    : string(1 to 6);
        variable stall_cycles : integer;
    begin
        wait until reset_done;
        wait until rising_edge(clk);
        if G_FNAME_SDI'length > 0 then  -- set G_FNAME_SDI = "" if sdi is not used (i.e., hash)
            file_open(sdi_file, G_FNAME_SDI, READ_MODE);

            while not endfile(sdi_file) loop
                readline(sdi_file, line_data);
                read(line_data, line_head, read_ok);
                if read_ok and (line_head = INS_HEAD or line_head = HDR_HEAD or line_head = DAT_HEAD) then
                    loop
                        lwc_hread(line_data, word_block, read_ok);
                        if not read_ok then
                            exit;
                        end if;
                        if G_TEST_MODE = 1 or G_TEST_MODE = 2 then
                            stall_cycles := get_stalls(G_TEST_ISSTALL);
                            if stall_cycles > 0 then
                                sdi_valid <= '0';
                                wait for stall_cycles * clk_period;
                            end if;
                        elsif G_TEST_MODE = TESTMODE_TIMING and not timing_started then
                            sdi_valid <= '0';
                            wait until timing_started;
                        end if;
                        sdi_valid <= '1';
                        sdi_data  <= word_block;
                        wait until rising_edge(clk) and sdi_ready = '1';
                    end loop;
                end if;
            end loop;
        end if;
        sdi_valid <= '0';
        wait;                           -- until simulation ends
    end process;

    --===========================================================================================--
    --=================================== DO Verification =======================================--
    tb_verify_do : process
        variable line_no      : integer := 0;
        variable line_data    : LINE;
        variable logMsg       : LINE;
        variable failMsg      : LINE;
        variable tb_block     : std_logic_vector(20 - 1 downto 0);
        variable word_block   : std_logic_vector(W - 1 downto 0);
        variable read_ok      : boolean;
        variable preamble     : string(1 to 6);
        variable word_count   : integer := 1;
        variable force_exit   : boolean := False;
        variable failed       : boolean := False;
        variable msgid        : integer;
        variable keyid        : integer;
        variable opcode       : std_logic_vector(3 downto 0);
        variable num_fails    : integer := 0;
        variable testcase     : integer := 0;
        variable stall_cycles : integer;
        variable cycles       : integer;
        variable end_cycle    : natural;
        variable end_time     : TIME;
    begin
        wait until reset_done;
        wait until rising_edge(clk);
        if G_TEST_MODE = TESTMODE_TIMING then
            file_open(timing_file, G_FNAME_TIMING, WRITE_MODE);
        end if;
        while not endfile(do_file) and not force_exit loop
            loop
                if endfile(do_file) then
                    report "Reached the end of " & G_FNAME_DO;
                    read_ok := False;
                    exit;
                end if;
                readline(do_file, line_data);
                line_no := line_no + 1;
                if line_data'length > 0 then
                    read(line_data, preamble, read_ok);
                    if read_ok then
                        exit;
                    end if;
                end if;
            end loop;
            if not read_ok then
                exit;
            end if;
            if preamble = EOF_HEAD then
                report "Reached EOF marker in " & G_FNAME_DO severity warning;
                force_exit := True;
                exit;
            elsif preamble = STT_HEAD or preamble = HDR_HEAD or preamble = DAT_HEAD then --valid  do.txt lines are: header, data, and status
                loop                    -- processing single line
                    lwc_hread(line_data, word_block, read_ok); -- read the rest of the line to word_block
                    if not read_ok then
                        exit;
                    end if;
                    -- stalls
                    if G_TEST_MODE = 1 or G_TEST_MODE = 3 then
                        stall_cycles := get_stalls(G_TEST_OSTALL);
                        if stall_cycles > 0 then
                            do_ready <= '0';
                            wait for stall_cycles * clk_period;
                            -- wait until rising_edge(clk);
                        end if;
                    elsif G_TEST_MODE = TESTMODE_TIMING and not timing_started then
                        -- stall until timing has started from PDI
                        do_ready       <= '0';
                        timing_stopped <= False;
                        wait until timing_started;
                    end if;
                    do_ready <= '1';
                    wait until rising_edge(clk) and do_valid = '1';
                    assert preamble /= STT_HEAD or do_last = '1' report "Status word received, but do_last was not '1'" severity error;
                    if not word_pass(do_sum, word_block) then
                        failed    := True;
                        write(logMsg, string'("[Log] Msg ID #") & integer'image(msgid) & string'(" fails at line #") & integer'image(line_no) & string'(" word #") & integer'image(word_count));
                        writeline(log_file, logMsg);
                        write(logMsg, string'("[Log]     Expected: ") & lwc_to_hstring(word_block) & string'(" Received: ") & lwc_to_hstring(do_sum));
                        writeline(log_file, logMsg);
                        report " --- MsgID #" & integer'image(testcase)
                                & " Data line #" & integer'image(line_no)
                                & " Word #" & integer'image(word_count)
                                & " at " & TIME'image(now) & " FAILS ---"
                        severity error;
                        report "Expected: " & lwc_to_hstring(word_block)
                                & "   Actual: " & lwc_to_hstring(do_sum) severity error;
                        write(result_file, string'("fail"));
                        num_fails := num_fails + 1;
                        write(failMsg, string'("Failure #") & integer'image(num_fails) & " MsgID: " & integer'image(testcase)); -- & " Operation: ");
                        write(failMsg, string'(" Line: ") & integer'image(line_no) & " Word: " & integer'image(word_count));
                        write(failMsg, " Expected: " & lwc_to_hstring(word_block) & " Received: " & lwc_to_hstring(do_data));
                        if PDI_SHARES > 1 then
                            write(failMsg, " Received sum: " & lwc_to_hstring(do_sum));
                        end if;
                        writeline(failures_file, failMsg);
                        if num_fails >= G_MAX_FAILURES then
                            force_exit := True;
                            exit;
                        end if;
                    else
                        write(logMsg, string'("[Log]     Expected: ") & lwc_to_hstring(word_block) & string'(" Received: ") & lwc_to_hstring(do_data) & string'(" Matched!"));
                        writeline(log_file, logMsg);
                    end if;
                    word_count := word_count + 1;
                    if preamble = STT_HEAD then -- last line of this testcase
                        if G_TEST_MODE = TESTMODE_TIMING then
                            assert timing_started;
                            cycles         := cycle_counter - start_cycle;
                            timing_stopped <= True;
                            do_ready       <= '0'; -- needed as we wait for de-assertion of timing_started
                            wait until not timing_started;
                            write(logMsg, integer'image(msgid) & ", " & integer'image(cycles));
                            writeline(timing_file, logMsg);
                            report "[Timing] MsgId: " & integer'image(msgid) & ", cycles: " & integer'image(cycles) severity note;
                        end if;
                    end if;
                end loop;               -- end of this line
            elsif preamble = TB_HEAD then
                testcase := testcase + 1;
                lwc_hread(line_data, tb_block, read_ok);
                if not read_ok then
                    exit;
                end if;
                opcode   := tb_block(19 downto 16);
                msgid    := to_integer(to_01(unsigned(tb_block(7 downto 0))));
                write(logMsg, "Testcase #" & integer'image(testcase) & " MsgID:" & integer'image(testcase) & " Op:");
                if (opcode = INST_HASH) then
                    write(logMsg, string'("HASH"));
                else
                    if opcode = INST_ENC then
                        write(logMsg, string'("ENC"));
                    elsif opcode = INST_DEC then
                        write(logMsg, string'("DEC"));
                    else
                        write(logMsg, string'("UNKNOWN opcode=") & lwc_to_hstring(opcode));
                    end if;
                    keyid := to_integer(to_01(unsigned(tb_block(15 downto 8))));
                    write(logMsg, string'(" KeyID:") & integer'image(keyid));
                end if;
                report logMsg.all severity note;
                writeline(log_file, logMsg);
            end if;
        end loop;
        --
        end_cycle  := cycle_counter;
        end_time   := now;
        do_ready   <= '0';
        wait until rising_edge(clk);
        if RW > 0 then
            report "Number of consumed random words: " & integer'image(num_rand_vectors) severity note;
        end if;
        --
        if failed then
            write(logMsg, string'("[FAIL] "));
        else
            write(logMsg, string'("[PASS] "));
        end if;
        file_close(do_file);
        write(logMsg, string'("Simulation completed in ") & integer'image(end_cycle) & " cycles.");
        -- write(logMsg, string'(" Simulation time: ") & time'image(end_time));
        writeline(log_file, logMsg);
        --
        if G_TEST_MODE = TESTMODE_TIMING then
            file_close(timing_file);
        end if;
        file_close(log_file);
        --
        if failed then
            write(result_file, "1");
            report LF & LF & logMsg.all & LF severity failure;
        else
            write(result_file, "0");
            report LF & LF & logMsg.all & LF severity note;
        end if;
        file_close(result_file);
        --
        stop_clock <= True;
        -- Do not use a 'failure' to end the simulation.
        -- Simulators usually exit when there are no event scheduled.
        wait;
    end process;

end architecture;
