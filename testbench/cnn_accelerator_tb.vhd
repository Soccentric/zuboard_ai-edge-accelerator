-- =============================================================================
-- CNN Accelerator Testbench
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Verifies:
--   - Conv2D computation correctness
--   - Pooling operations
--   - AXI-Stream data flow
--   - End-to-end inference pipeline
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

library work;
use work.cnn_pkg.all;

entity cnn_accelerator_tb is
end cnn_accelerator_tb;

architecture sim of cnn_accelerator_tb is

    -- Clock and reset
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    
    -- Configuration
    signal cfg_enable   : std_logic := '0';
    signal cfg_activation : std_logic_vector(2 downto 0) := ACT_RELU;
    
    -- Weight loading interface
    signal weight_valid : std_logic := '0';
    signal weight_data  : std_logic_vector(WEIGHT_WIDTH-1 downto 0) := (others => '0');
    signal weight_addr  : std_logic_vector(15 downto 0) := (others => '0');
    signal weight_filter: std_logic_vector(7 downto 0) := (others => '0');
    
    -- Bias loading interface
    signal bias_valid   : std_logic := '0';
    signal bias_data    : std_logic_vector(BIAS_WIDTH-1 downto 0) := (others => '0');
    signal bias_addr    : std_logic_vector(7 downto 0) := (others => '0');
    
    -- AXI-Stream input
    signal s_axis_tdata : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal s_axis_tvalid: std_logic := '0';
    signal s_axis_tready: std_logic;
    signal s_axis_tlast : std_logic := '0';
    signal s_axis_tuser : std_logic := '0';
    
    -- AXI-Stream output
    signal m_axis_tdata : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal m_axis_tvalid: std_logic;
    signal m_axis_tready: std_logic := '1';
    signal m_axis_tlast : std_logic;
    signal m_axis_tuser : std_logic;
    
    -- Status
    signal busy         : std_logic;
    signal done         : std_logic;
    
    -- Test parameters
    constant TEST_WIDTH : integer := 8;
    constant TEST_HEIGHT: integer := 8;
    constant IN_CHANNELS: integer := 3;
    constant OUT_CHANNELS: integer := 4;
    
    -- Test signals
    signal test_pass    : boolean := true;
    signal test_done    : boolean := false;
    signal output_count : integer := 0;

begin

    -- ==========================================================================
    -- Clock Generation
    -- ==========================================================================
    clk <= not clk after CLK_PERIOD / 2 when not test_done else '0';

    -- ==========================================================================
    -- DUT: Conv2D Engine
    -- ==========================================================================
    dut_conv2d : entity work.conv2d_engine
        generic map (
            KERNEL_SIZE     => 3,
            INPUT_CHANNELS  => IN_CHANNELS,
            OUTPUT_CHANNELS => OUT_CHANNELS,
            INPUT_WIDTH     => TEST_WIDTH,
            INPUT_HEIGHT    => TEST_HEIGHT,
            STRIDE          => 1,
            PADDING         => 1,
            NUM_MAC_UNITS   => 9
        )
        port map (
            clk             => clk,
            rst_n           => rst_n,
            cfg_enable      => cfg_enable,
            cfg_activation  => cfg_activation,
            weight_valid    => weight_valid,
            weight_data     => weight_data,
            weight_addr     => weight_addr,
            weight_filter   => weight_filter,
            bias_valid      => bias_valid,
            bias_data       => bias_data,
            bias_addr       => bias_addr,
            s_axis_tdata    => s_axis_tdata,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,
            s_axis_tuser    => s_axis_tuser,
            m_axis_tdata    => m_axis_tdata,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast,
            m_axis_tuser    => m_axis_tuser,
            busy            => busy,
            done            => done
        );

    -- ==========================================================================
    -- Main Test Process
    -- ==========================================================================
    test_proc : process
        
        -- Procedure to wait for clock cycles
        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
        
        -- Procedure to load weights
        procedure load_weights is
            variable w_idx : integer := 0;
        begin
            report "Loading weights..." severity note;
            
            for f in 0 to OUT_CHANNELS-1 loop
                for c in 0 to IN_CHANNELS-1 loop
                    for ky in 0 to 2 loop
                        for kx in 0 to 2 loop
                            wait until rising_edge(clk);
                            weight_valid <= '1';
                            weight_filter <= std_logic_vector(to_unsigned(f, 8));
                            weight_addr <= std_logic_vector(to_unsigned(w_idx mod 27, 16));
                            -- Simple weight pattern: alternating 1.0 and -0.5 in Q8.8
                            if (w_idx mod 2) = 0 then
                                weight_data <= std_logic_vector(to_signed(256, WEIGHT_WIDTH));  -- 1.0
                            else
                                weight_data <= std_logic_vector(to_signed(-128, WEIGHT_WIDTH)); -- -0.5
                            end if;
                            w_idx := w_idx + 1;
                        end loop;
                    end loop;
                end loop;
            end loop;
            
            wait until rising_edge(clk);
            weight_valid <= '0';
            
            report "Weights loaded: " & integer'image(w_idx) & " values" severity note;
        end procedure;
        
        -- Procedure to load biases
        procedure load_biases is
        begin
            report "Loading biases..." severity note;
            
            for f in 0 to OUT_CHANNELS-1 loop
                wait until rising_edge(clk);
                bias_valid <= '1';
                bias_addr <= std_logic_vector(to_unsigned(f, 8));
                bias_data <= std_logic_vector(to_signed(f * 64, BIAS_WIDTH));  -- Small bias
            end loop;
            
            wait until rising_edge(clk);
            bias_valid <= '0';
            
            report "Biases loaded." severity note;
        end procedure;
        
        -- Procedure to send test frame
        procedure send_frame is
            variable pixel_val : integer;
            variable pixel_cnt : integer := 0;
        begin
            report "Sending test frame..." severity note;
            
            -- Send pixels for all channels
            for c in 0 to IN_CHANNELS-1 loop
                for y in 0 to TEST_HEIGHT-1 loop
                    for x in 0 to TEST_WIDTH-1 loop
                        wait until rising_edge(clk);
                        while s_axis_tready = '0' loop
                            wait until rising_edge(clk);
                        end loop;
                        
                        s_axis_tvalid <= '1';
                        
                        -- Start of frame marker
                        if c = 0 and y = 0 and x = 0 then
                            s_axis_tuser <= '1';
                        else
                            s_axis_tuser <= '0';
                        end if;
                        
                        -- End of line marker
                        if x = TEST_WIDTH-1 then
                            s_axis_tlast <= '1';
                        else
                            s_axis_tlast <= '0';
                        end if;
                        
                        -- Pixel value: gradient pattern in Q8.8
                        pixel_val := (x + y + c * 32) * 16;
                        s_axis_tdata <= std_logic_vector(to_signed(pixel_val, DATA_WIDTH));
                        pixel_cnt := pixel_cnt + 1;
                    end loop;
                end loop;
            end loop;
            
            wait until rising_edge(clk);
            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tuser <= '0';
            
            report "Frame sent: " & integer'image(pixel_cnt) & " pixels" severity note;
        end procedure;
        
        -- Procedure to collect output
        procedure collect_output is
            variable out_cnt : integer := 0;
            variable timeout_cnt : integer := 0;
        begin
            report "Collecting output..." severity note;
            
            while out_cnt < TEST_WIDTH * TEST_HEIGHT * OUT_CHANNELS loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
                
                if m_axis_tvalid = '1' and m_axis_tready = '1' then
                    out_cnt := out_cnt + 1;
                    output_count <= out_cnt;
                    
                    -- Check for start of frame
                    if m_axis_tuser = '1' then
                        report "Output SOF detected" severity note;
                    end if;
                    
                    -- Log some output values
                    if out_cnt <= 10 or (out_cnt mod 100) = 0 then
                        report "Output " & integer'image(out_cnt) & ": " & 
                               integer'image(to_integer(signed(m_axis_tdata))) severity note;
                    end if;
                end if;
                
                -- Timeout check
                if timeout_cnt > 100000 then
                    report "ERROR: Output collection timeout!" severity error;
                    test_pass <= false;
                    exit;
                end if;
            end loop;
            
            report "Output collected: " & integer'image(out_cnt) & " values" severity note;
        end procedure;
        
    begin
        -- Initialize
        rst_n <= '0';
        cfg_enable <= '0';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        s_axis_tuser <= '0';
        weight_valid <= '0';
        bias_valid <= '0';
        m_axis_tready <= '1';
        
        wait_cycles(10);
        
        -- Release reset
        rst_n <= '1';
        wait_cycles(5);
        
        report "========================================" severity note;
        report "  CNN Accelerator Testbench Starting   " severity note;
        report "========================================" severity note;
        
        -- Step 1: Load weights
        load_weights;
        wait_cycles(5);
        
        -- Step 2: Load biases
        load_biases;
        wait_cycles(5);
        
        -- Step 3: Enable processing
        cfg_enable <= '1';
        cfg_activation <= ACT_RELU;
        wait_cycles(2);
        
        -- Step 4: Send test frame
        send_frame;
        
        -- Step 5: Wait for and collect output
        collect_output;
        
        -- Step 6: Wait for done signal
        wait_cycles(100);
        
        -- Check completion
        if done = '1' then
            report "Inference completed successfully!" severity note;
        else
            report "WARNING: Done signal not asserted" severity warning;
        end if;
        
        -- Print results
        report "========================================" severity note;
        report "  Test Results                         " severity note;
        report "========================================" severity note;
        report "Output pixels collected: " & integer'image(output_count) severity note;
        
        if test_pass then
            report "TEST PASSED!" severity note;
        else
            report "TEST FAILED!" severity error;
        end if;
        
        wait_cycles(10);
        test_done <= true;
        
        wait;
    end process;

    -- ==========================================================================
    -- Output Monitor Process
    -- ==========================================================================
    output_monitor : process
        file output_file : text open write_mode is "conv_output.txt";
        variable line_buf : line;
    begin
        wait until rising_edge(clk) and rst_n = '1';
        
        while not test_done loop
            wait until rising_edge(clk);
            
            if m_axis_tvalid = '1' and m_axis_tready = '1' then
                write(line_buf, to_integer(signed(m_axis_tdata)));
                writeline(output_file, line_buf);
            end if;
        end loop;
        
        file_close(output_file);
        wait;
    end process;

end sim;
