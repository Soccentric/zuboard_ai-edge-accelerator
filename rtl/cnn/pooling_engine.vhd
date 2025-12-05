-- =============================================================================
-- Max/Average Pooling Engine with AXI-Stream Interface
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Features:
--   - Configurable pool size (2x2, 3x3)
--   - Max pooling and average pooling modes
--   - Configurable stride
--   - Line buffer based streaming architecture
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity pooling_engine is
    generic (
        POOL_SIZE       : integer := 2;
        INPUT_WIDTH     : integer := 64;
        INPUT_HEIGHT    : integer := 64;
        INPUT_CHANNELS  : integer := 16;
        STRIDE          : integer := 2
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_enable      : in  std_logic;
        cfg_pool_type   : in  std_logic;  -- '0' = max, '1' = average
        
        -- AXI-Stream Input
        s_axis_tdata    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tuser    : in  std_logic;
        
        -- AXI-Stream Output
        m_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic;
        
        -- Status
        busy            : out std_logic
    );
end pooling_engine;

architecture rtl of pooling_engine is

    -- Output dimensions
    constant OUT_WIDTH  : integer := INPUT_WIDTH / STRIDE;
    constant OUT_HEIGHT : integer := INPUT_HEIGHT / STRIDE;
    
    -- Line buffer for pooling window
    type line_buf_array_t is array (0 to POOL_SIZE-2) of line_buffer_t;
    signal line_buffers : line_buf_array_t;
    
    -- Pooling window (2x2 or 3x3)
    type pool_window_t is array (0 to POOL_SIZE-1, 0 to POOL_SIZE-1) of pixel_t;
    signal pool_window  : pool_window_t;
    signal window_valid : std_logic;
    
    -- Position counters
    signal x_pos        : unsigned(11 downto 0);
    signal y_pos        : unsigned(11 downto 0);
    signal ch_idx       : unsigned(9 downto 0);
    
    -- Write address for line buffer
    signal lb_wr_addr   : unsigned(11 downto 0);
    
    -- Pool results
    signal max_result   : pixel_t;
    signal avg_result   : pixel_t;
    signal pool_result  : pixel_t;
    
    -- Pipeline registers
    signal valid_d      : std_logic_vector(2 downto 0);
    signal last_d       : std_logic_vector(2 downto 0);
    signal user_d       : std_logic_vector(2 downto 0);
    
    -- Control
    signal output_strobe : std_logic;
    signal input_accept  : std_logic;

begin

    -- ==========================================================================
    -- Line Buffer Write
    -- ==========================================================================
    gen_line_buffers: for i in 0 to POOL_SIZE-2 generate
        process(clk)
        begin
            if rising_edge(clk) then
                if s_axis_tvalid = '1' and input_accept = '1' then
                    line_buffers(i)(to_integer(lb_wr_addr)) <= signed(s_axis_tdata);
                end if;
            end if;
        end process;
    end generate;

    -- ==========================================================================
    -- Position and Address Counter
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            x_pos <= (others => '0');
            y_pos <= (others => '0');
            ch_idx <= (others => '0');
            lb_wr_addr <= (others => '0');
        elsif rising_edge(clk) then
            if s_axis_tuser = '1' and s_axis_tvalid = '1' then
                -- Start of frame
                x_pos <= (others => '0');
                y_pos <= (others => '0');
                ch_idx <= (others => '0');
                lb_wr_addr <= (others => '0');
            elsif s_axis_tvalid = '1' and input_accept = '1' then
                -- Update write address
                if lb_wr_addr = INPUT_WIDTH - 1 then
                    lb_wr_addr <= (others => '0');
                else
                    lb_wr_addr <= lb_wr_addr + 1;
                end if;
                
                -- Update position
                if x_pos = INPUT_WIDTH - 1 then
                    x_pos <= (others => '0');
                    if y_pos = INPUT_HEIGHT - 1 then
                        y_pos <= (others => '0');
                        if ch_idx = INPUT_CHANNELS - 1 then
                            ch_idx <= (others => '0');
                        else
                            ch_idx <= ch_idx + 1;
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
    -- Pooling Window Generation
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            for i in 0 to POOL_SIZE-1 loop
                for j in 0 to POOL_SIZE-1 loop
                    pool_window(i, j) <= (others => '0');
                end loop;
            end loop;
        elsif rising_edge(clk) then
            if s_axis_tvalid = '1' and input_accept = '1' then
                -- Shift window horizontally
                for i in 0 to POOL_SIZE-1 loop
                    for j in 0 to POOL_SIZE-2 loop
                        pool_window(i, j) <= pool_window(i, j+1);
                    end loop;
                end loop;
                
                -- Load new column
                for i in 0 to POOL_SIZE-2 loop
                    pool_window(i, POOL_SIZE-1) <= line_buffers(POOL_SIZE-2-i)(to_integer(lb_wr_addr));
                end loop;
                pool_window(POOL_SIZE-1, POOL_SIZE-1) <= signed(s_axis_tdata);
            end if;
        end if;
    end process;
    
    -- Window valid when at pooling output position
    window_valid <= '1' when (x_pos(STRIDE-1 downto 0) = STRIDE-1 and 
                              y_pos(STRIDE-1 downto 0) = STRIDE-1 and
                              y_pos >= POOL_SIZE-1 and
                              x_pos >= POOL_SIZE-1) else '0';

    -- ==========================================================================
    -- Max Pooling (2x2)
    -- ==========================================================================
    gen_max_pool_2x2: if POOL_SIZE = 2 generate
        process(clk)
            variable max_val : pixel_t;
        begin
            if rising_edge(clk) then
                -- Compare all 4 values
                max_val := pool_window(0, 0);
                
                if pool_window(0, 1) > max_val then
                    max_val := pool_window(0, 1);
                end if;
                if pool_window(1, 0) > max_val then
                    max_val := pool_window(1, 0);
                end if;
                if pool_window(1, 1) > max_val then
                    max_val := pool_window(1, 1);
                end if;
                
                max_result <= max_val;
            end if;
        end process;
    end generate;
    
    gen_max_pool_3x3: if POOL_SIZE = 3 generate
        process(clk)
            variable max_val : pixel_t;
        begin
            if rising_edge(clk) then
                max_val := pool_window(0, 0);
                
                for i in 0 to 2 loop
                    for j in 0 to 2 loop
                        if pool_window(i, j) > max_val then
                            max_val := pool_window(i, j);
                        end if;
                    end loop;
                end loop;
                
                max_result <= max_val;
            end if;
        end process;
    end generate;

    -- ==========================================================================
    -- Average Pooling
    -- ==========================================================================
    gen_avg_pool_2x2: if POOL_SIZE = 2 generate
        process(clk)
            variable sum : signed(DATA_WIDTH+1 downto 0);
        begin
            if rising_edge(clk) then
                sum := resize(pool_window(0, 0), DATA_WIDTH+2) +
                       resize(pool_window(0, 1), DATA_WIDTH+2) +
                       resize(pool_window(1, 0), DATA_WIDTH+2) +
                       resize(pool_window(1, 1), DATA_WIDTH+2);
                -- Divide by 4 (shift right by 2)
                avg_result <= sum(DATA_WIDTH+1 downto 2);
            end if;
        end process;
    end generate;
    
    gen_avg_pool_3x3: if POOL_SIZE = 3 generate
        process(clk)
            variable sum : signed(DATA_WIDTH+3 downto 0);
            variable avg : signed(DATA_WIDTH+3 downto 0);
        begin
            if rising_edge(clk) then
                sum := (others => '0');
                for i in 0 to 2 loop
                    for j in 0 to 2 loop
                        sum := sum + resize(pool_window(i, j), DATA_WIDTH+4);
                    end loop;
                end loop;
                -- Divide by 9: multiply by 1/9 ~= 7282/65536 (approximate)
                -- Or use shift-add: x/9 ≈ (x * 7) / 64 for quick approximation
                avg := shift_right(sum * 7, 6);
                avg_result <= avg(DATA_WIDTH-1 downto 0);
            end if;
        end process;
    end generate;

    -- ==========================================================================
    -- Pool Type Selection
    -- ==========================================================================
    pool_result <= avg_result when cfg_pool_type = '1' else max_result;

    -- ==========================================================================
    -- Pipeline Registers
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid_d <= (others => '0');
            last_d <= (others => '0');
            user_d <= (others => '0');
        elsif rising_edge(clk) then
            valid_d(0) <= window_valid and s_axis_tvalid and cfg_enable;
            valid_d(2 downto 1) <= valid_d(1 downto 0);
            
            last_d(0) <= s_axis_tlast and window_valid;
            last_d(2 downto 1) <= last_d(1 downto 0);
            
            user_d(0) <= s_axis_tuser;
            user_d(2 downto 1) <= user_d(1 downto 0);
        end if;
    end process;

    -- ==========================================================================
    -- Output Assignment
    -- ==========================================================================
    input_accept <= cfg_enable and (m_axis_tready or not valid_d(2));
    s_axis_tready <= input_accept;
    
    m_axis_tdata <= std_logic_vector(pool_result);
    m_axis_tvalid <= valid_d(2);
    m_axis_tlast <= last_d(2);
    m_axis_tuser <= user_d(2);
    
    busy <= cfg_enable;

end rtl;
