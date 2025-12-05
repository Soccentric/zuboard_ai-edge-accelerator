-- =============================================================================
-- Conv2D Processing Engine - 3x3 Convolution with AXI-Stream Interface
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Features:
--   - Configurable kernel size (1x1, 3x3, 5x5)
--   - Line buffer for streaming convolution
--   - Parallel MAC units for high throughput
--   - Integrated bias addition and activation
--   - AXI-Stream input/output interfaces
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity conv2d_engine is
    generic (
        KERNEL_SIZE     : integer := 3;
        INPUT_CHANNELS  : integer := 3;
        OUTPUT_CHANNELS : integer := 16;
        INPUT_WIDTH     : integer := 128;
        INPUT_HEIGHT    : integer := 128;
        STRIDE          : integer := 1;
        PADDING         : integer := 1;
        NUM_MAC_UNITS   : integer := 9     -- Parallel MACs (3x3 kernel)
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration interface
        cfg_enable      : in  std_logic;
        cfg_activation  : in  std_logic_vector(2 downto 0);
        
        -- Weight loading interface
        weight_valid    : in  std_logic;
        weight_data     : in  std_logic_vector(WEIGHT_WIDTH-1 downto 0);
        weight_addr     : in  std_logic_vector(15 downto 0);
        weight_filter   : in  std_logic_vector(7 downto 0);
        
        -- Bias loading interface
        bias_valid      : in  std_logic;
        bias_data       : in  std_logic_vector(BIAS_WIDTH-1 downto 0);
        bias_addr       : in  std_logic_vector(7 downto 0);
        
        -- AXI-Stream Input
        s_axis_tdata    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tuser    : in  std_logic;  -- Start of frame
        
        -- AXI-Stream Output
        m_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic;  -- Start of frame
        
        -- Status
        busy            : out std_logic;
        done            : out std_logic
    );
end conv2d_engine;

architecture rtl of conv2d_engine is

    -- Calculate output dimensions
    constant OUT_WIDTH  : integer := (INPUT_WIDTH + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;
    constant OUT_HEIGHT : integer := (INPUT_HEIGHT + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;
    
    -- Line buffer signals
    type line_buf_array_t is array (0 to KERNEL_SIZE-2) of line_buffer_t;
    signal line_buffers : line_buf_array_t;
    signal lb_wr_addr   : unsigned(11 downto 0);
    signal lb_rd_addr   : unsigned(11 downto 0);
    
    -- Sliding window
    signal pixel_window : window_3x3_t;
    signal window_valid : std_logic;
    
    -- Weight memory (BRAM-based)
    type weight_mem_t is array (0 to KERNEL_SIZE*KERNEL_SIZE*INPUT_CHANNELS-1) of weight_t;
    type weight_bank_t is array (0 to OUTPUT_CHANNELS-1) of weight_mem_t;
    signal weight_mem   : weight_bank_t;
    
    -- Bias memory
    type bias_mem_t is array (0 to OUTPUT_CHANNELS-1) of bias_t;
    signal bias_mem     : bias_mem_t;
    
    -- Position counters
    signal x_pos        : unsigned(11 downto 0);
    signal y_pos        : unsigned(11 downto 0);
    signal ch_in        : unsigned(9 downto 0);
    signal ch_out       : unsigned(9 downto 0);
    
    -- MAC accumulator
    signal mac_acc      : acc_t;
    signal mac_result   : pixel_t;
    
    -- Pipeline registers
    signal pipe_valid   : std_logic_vector(4 downto 0);
    signal pipe_last    : std_logic_vector(4 downto 0);
    signal pipe_user    : std_logic_vector(4 downto 0);
    
    -- FSM states
    type state_t is (IDLE, FILL_BUFFER, CONVOLVE, OUTPUT_RESULT, WAIT_READY);
    signal state        : state_t;
    signal next_state   : state_t;
    
    -- Activation applied result
    signal activated_result : pixel_t;
    
    -- Internal signals
    signal input_ready  : std_logic;
    signal output_valid : std_logic;
    signal frame_done   : std_logic;

begin

    -- ==========================================================================
    -- Weight Memory Write Process
    -- ==========================================================================
    process(clk)
        variable filter_idx : integer;
        variable weight_idx : integer;
    begin
        if rising_edge(clk) then
            if weight_valid = '1' then
                filter_idx := to_integer(unsigned(weight_filter));
                weight_idx := to_integer(unsigned(weight_addr));
                if filter_idx < OUTPUT_CHANNELS and weight_idx < KERNEL_SIZE*KERNEL_SIZE*INPUT_CHANNELS then
                    weight_mem(filter_idx)(weight_idx) <= signed(weight_data);
                end if;
            end if;
        end if;
    end process;
    
    -- ==========================================================================
    -- Bias Memory Write Process
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if bias_valid = '1' then
                if to_integer(unsigned(bias_addr)) < OUTPUT_CHANNELS then
                    bias_mem(to_integer(unsigned(bias_addr))) <= signed(bias_data);
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Line Buffer Control
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            lb_wr_addr <= (others => '0');
            lb_rd_addr <= (others => '0');
        elsif rising_edge(clk) then
            if s_axis_tvalid = '1' and input_ready = '1' then
                -- Write to line buffer
                lb_wr_addr <= lb_wr_addr + 1;
                if lb_wr_addr = INPUT_WIDTH - 1 then
                    lb_wr_addr <= (others => '0');
                end if;
            end if;
        end if;
    end process;
    
    -- Line buffer shift register (stores previous rows)
    gen_line_buffers: for i in 0 to KERNEL_SIZE-2 generate
        process(clk)
        begin
            if rising_edge(clk) then
                if s_axis_tvalid = '1' and input_ready = '1' then
                    line_buffers(i)(to_integer(lb_wr_addr)) <= signed(s_axis_tdata);
                end if;
            end if;
        end process;
    end generate;

    -- ==========================================================================
    -- Sliding Window Generation (3x3)
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            for i in 0 to 2 loop
                for j in 0 to 2 loop
                    pixel_window(i, j) <= (others => '0');
                end loop;
            end loop;
            window_valid <= '0';
        elsif rising_edge(clk) then
            if s_axis_tvalid = '1' and input_ready = '1' then
                -- Shift window horizontally
                for i in 0 to 2 loop
                    pixel_window(i, 0) <= pixel_window(i, 1);
                    pixel_window(i, 1) <= pixel_window(i, 2);
                end loop;
                
                -- Load new column from line buffers and input
                if KERNEL_SIZE >= 3 then
                    pixel_window(0, 2) <= line_buffers(1)(to_integer(lb_rd_addr));
                    pixel_window(1, 2) <= line_buffers(0)(to_integer(lb_rd_addr));
                end if;
                pixel_window(2, 2) <= signed(s_axis_tdata);
                
                -- Window is valid after filling
                if y_pos >= KERNEL_SIZE-1 and x_pos >= KERNEL_SIZE-1 then
                    window_valid <= '1';
                else
                    window_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Position Counter
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            x_pos <= (others => '0');
            y_pos <= (others => '0');
            ch_in <= (others => '0');
            ch_out <= (others => '0');
        elsif rising_edge(clk) then
            if s_axis_tuser = '1' and s_axis_tvalid = '1' then
                -- Start of new frame
                x_pos <= (others => '0');
                y_pos <= (others => '0');
                ch_in <= (others => '0');
            elsif s_axis_tvalid = '1' and input_ready = '1' then
                -- Advance position
                if x_pos = INPUT_WIDTH - 1 then
                    x_pos <= (others => '0');
                    if y_pos = INPUT_HEIGHT - 1 then
                        y_pos <= (others => '0');
                        if ch_in = INPUT_CHANNELS - 1 then
                            ch_in <= (others => '0');
                        else
                            ch_in <= ch_in + 1;
                        end if;
                    else
                        y_pos <= y_pos + 1;
                    end if;
                else
                    x_pos <= x_pos + 1;
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Convolution MAC Array (3x3 kernel, parallel computation)
    -- ==========================================================================
    process(clk, rst_n)
        variable mac_sum : acc_t;
        variable weight_idx : integer;
    begin
        if rst_n = '0' then
            mac_acc <= (others => '0');
            mac_result <= (others => '0');
        elsif rising_edge(clk) then
            if window_valid = '1' and cfg_enable = '1' then
                mac_sum := (others => '0');
                
                -- Compute 3x3 convolution (all 9 MACs in parallel)
                for ky in 0 to KERNEL_SIZE-1 loop
                    for kx in 0 to KERNEL_SIZE-1 loop
                        weight_idx := ky * KERNEL_SIZE + kx + to_integer(ch_in) * KERNEL_SIZE * KERNEL_SIZE;
                        if weight_idx < KERNEL_SIZE*KERNEL_SIZE*INPUT_CHANNELS then
                            mac_sum := mac_sum + fp_mult(
                                pixel_window(ky, kx),
                                weight_mem(to_integer(ch_out))(weight_idx)
                            );
                        end if;
                    end loop;
                end loop;
                
                -- Accumulate across input channels
                if ch_in = 0 then
                    mac_acc <= mac_sum;
                else
                    mac_acc <= mac_acc + mac_sum;
                end if;
                
                -- Final result with bias when all channels processed
                if ch_in = INPUT_CHANNELS - 1 then
                    mac_result <= trunc_acc(mac_acc + mac_sum + resize(bias_mem(to_integer(ch_out)), ACC_WIDTH));
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Activation Function
    -- ==========================================================================
    process(mac_result, cfg_activation)
    begin
        case cfg_activation is
            when ACT_RELU =>
                activated_result <= relu(mac_result);
            when ACT_RELU6 =>
                activated_result <= relu6(mac_result);
            when ACT_LEAKY_RELU =>
                activated_result <= leaky_relu(mac_result);
            when others =>
                activated_result <= mac_result;  -- No activation
        end case;
    end process;

    -- ==========================================================================
    -- Pipeline Control
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            pipe_valid <= (others => '0');
            pipe_last <= (others => '0');
            pipe_user <= (others => '0');
        elsif rising_edge(clk) then
            -- Shift pipeline
            pipe_valid(0) <= window_valid and cfg_enable;
            pipe_valid(4 downto 1) <= pipe_valid(3 downto 0);
            
            pipe_last(0) <= s_axis_tlast;
            pipe_last(4 downto 1) <= pipe_last(3 downto 0);
            
            pipe_user(0) <= s_axis_tuser;
            pipe_user(4 downto 1) <= pipe_user(3 downto 0);
        end if;
    end process;

    -- ==========================================================================
    -- FSM: Control Logic
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;
    
    process(state, cfg_enable, s_axis_tvalid, s_axis_tuser, window_valid, 
            m_axis_tready, y_pos, x_pos, ch_out)
    begin
        next_state <= state;
        
        case state is
            when IDLE =>
                if cfg_enable = '1' and s_axis_tvalid = '1' and s_axis_tuser = '1' then
                    next_state <= FILL_BUFFER;
                end if;
                
            when FILL_BUFFER =>
                if y_pos >= KERNEL_SIZE-1 and x_pos >= KERNEL_SIZE-1 then
                    next_state <= CONVOLVE;
                end if;
                
            when CONVOLVE =>
                if y_pos = INPUT_HEIGHT - 1 and x_pos = INPUT_WIDTH - 1 then
                    next_state <= OUTPUT_RESULT;
                end if;
                
            when OUTPUT_RESULT =>
                if m_axis_tready = '1' then
                    if ch_out = OUTPUT_CHANNELS - 1 then
                        next_state <= IDLE;
                    else
                        next_state <= WAIT_READY;
                    end if;
                end if;
                
            when WAIT_READY =>
                if m_axis_tready = '1' then
                    next_state <= CONVOLVE;
                end if;
                
            when others =>
                next_state <= IDLE;
        end case;
    end process;

    -- ==========================================================================
    -- Output Assignment
    -- ==========================================================================
    input_ready <= '1' when (state = FILL_BUFFER or state = CONVOLVE) and cfg_enable = '1' else '0';
    s_axis_tready <= input_ready;
    
    output_valid <= pipe_valid(4) and cfg_enable when ch_in = INPUT_CHANNELS - 1 else '0';
    m_axis_tvalid <= output_valid;
    m_axis_tdata <= std_logic_vector(activated_result);
    m_axis_tlast <= pipe_last(4) and output_valid;
    m_axis_tuser <= pipe_user(4) and output_valid;
    
    busy <= '1' when state /= IDLE else '0';
    done <= '1' when state = OUTPUT_RESULT and ch_out = OUTPUT_CHANNELS - 1 else '0';

end rtl;
