-- =============================================================================
-- Frame Buffer Controller with Triple Buffering
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Features:
--   - Triple buffering for glitch-free frame switching
--   - AXI-Stream input from camera/DMA
--   - AXI-Stream output to CNN pipeline
--   - Configurable frame dimensions
--   - DDR memory interface via AXI4
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity frame_buffer_ctrl is
    generic (
        FRAME_WIDTH     : integer := 128;
        FRAME_HEIGHT    : integer := 128;
        PIXEL_WIDTH     : integer := 24;        -- RGB888
        NUM_BUFFERS     : integer := 3;         -- Triple buffering
        BASE_ADDR       : std_logic_vector(31 downto 0) := x"10000000";
        BURST_LEN       : integer := 16
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_enable      : in  std_logic;
        cfg_frame_width : in  std_logic_vector(11 downto 0);
        cfg_frame_height: in  std_logic_vector(11 downto 0);
        
        -- AXI-Stream Input (from camera/DMA)
        s_axis_tdata    : in  std_logic_vector(PIXEL_WIDTH-1 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tuser    : in  std_logic;  -- SOF
        
        -- AXI-Stream Output (to CNN pipeline)
        m_axis_tdata    : out std_logic_vector(PIXEL_WIDTH-1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic;  -- SOF
        
        -- AXI4 Memory Interface (simplified)
        m_axi_awaddr    : out std_logic_vector(31 downto 0);
        m_axi_awlen     : out std_logic_vector(7 downto 0);
        m_axi_awsize    : out std_logic_vector(2 downto 0);
        m_axi_awburst   : out std_logic_vector(1 downto 0);
        m_axi_awvalid   : out std_logic;
        m_axi_awready   : in  std_logic;
        m_axi_wdata     : out std_logic_vector(63 downto 0);
        m_axi_wstrb     : out std_logic_vector(7 downto 0);
        m_axi_wlast     : out std_logic;
        m_axi_wvalid    : out std_logic;
        m_axi_wready    : in  std_logic;
        m_axi_bresp     : in  std_logic_vector(1 downto 0);
        m_axi_bvalid    : in  std_logic;
        m_axi_bready    : out std_logic;
        
        m_axi_araddr    : out std_logic_vector(31 downto 0);
        m_axi_arlen     : out std_logic_vector(7 downto 0);
        m_axi_arsize    : out std_logic_vector(2 downto 0);
        m_axi_arburst   : out std_logic_vector(1 downto 0);
        m_axi_arvalid   : out std_logic;
        m_axi_arready   : in  std_logic;
        m_axi_rdata     : in  std_logic_vector(63 downto 0);
        m_axi_rresp     : in  std_logic_vector(1 downto 0);
        m_axi_rlast     : in  std_logic;
        m_axi_rvalid    : in  std_logic;
        m_axi_rready    : out std_logic;
        
        -- Status
        write_buf_idx   : out std_logic_vector(1 downto 0);
        read_buf_idx    : out std_logic_vector(1 downto 0);
        frame_complete  : out std_logic
    );
end frame_buffer_ctrl;

architecture rtl of frame_buffer_ctrl is

    -- Frame size calculation
    constant FRAME_SIZE : integer := FRAME_WIDTH * FRAME_HEIGHT;
    constant BYTES_PER_PIXEL : integer := (PIXEL_WIDTH + 7) / 8;
    constant FRAME_BYTES : integer := FRAME_SIZE * BYTES_PER_PIXEL;
    
    -- Buffer addresses (each buffer is FRAME_BYTES apart)
    type buf_addr_array_t is array (0 to NUM_BUFFERS-1) of std_logic_vector(31 downto 0);
    signal buf_base_addr : buf_addr_array_t;
    
    -- Buffer management
    signal wr_buf       : unsigned(1 downto 0);
    signal rd_buf       : unsigned(1 downto 0);
    signal ready_buf    : unsigned(1 downto 0);
    
    -- Write FSM
    type wr_state_t is (WR_IDLE, WR_WAIT_SOF, WR_WRITE_ADDR, WR_WRITE_DATA, WR_WAIT_RESP);
    signal wr_state     : wr_state_t;
    
    -- Read FSM
    type rd_state_t is (RD_IDLE, RD_SEND_SOF, RD_READ_ADDR, RD_READ_DATA, RD_OUTPUT);
    signal rd_state     : rd_state_t;
    
    -- Write position tracking
    signal wr_x         : unsigned(11 downto 0);
    signal wr_y         : unsigned(11 downto 0);
    signal wr_addr      : unsigned(31 downto 0);
    signal wr_burst_cnt : unsigned(7 downto 0);
    
    -- Read position tracking
    signal rd_x         : unsigned(11 downto 0);
    signal rd_y         : unsigned(11 downto 0);
    signal rd_addr      : unsigned(31 downto 0);
    signal rd_burst_cnt : unsigned(7 downto 0);
    
    -- FIFO for pixel packing (input)
    signal wr_fifo_data : std_logic_vector(63 downto 0);
    signal wr_fifo_wr   : std_logic;
    signal wr_fifo_rd   : std_logic;
    signal wr_fifo_cnt  : unsigned(3 downto 0);
    
    -- FIFO for pixel unpacking (output)
    signal rd_fifo_data : std_logic_vector(63 downto 0);
    signal rd_fifo_valid: std_logic;
    signal rd_pixel_idx : unsigned(1 downto 0);
    
    -- Internal signals
    signal input_ready  : std_logic;
    signal output_valid : std_logic;
    signal frame_done   : std_logic;

begin

    -- ==========================================================================
    -- Buffer Address Calculation
    -- ==========================================================================
    gen_buf_addr: for i in 0 to NUM_BUFFERS-1 generate
        buf_base_addr(i) <= std_logic_vector(unsigned(BASE_ADDR) + to_unsigned(i * FRAME_BYTES, 32));
    end generate;

    -- ==========================================================================
    -- Write State Machine (Camera to DDR)
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            wr_state <= WR_IDLE;
            wr_x <= (others => '0');
            wr_y <= (others => '0');
            wr_addr <= (others => '0');
            wr_burst_cnt <= (others => '0');
            wr_buf <= (others => '0');
        elsif rising_edge(clk) then
            case wr_state is
                when WR_IDLE =>
                    if cfg_enable = '1' then
                        wr_state <= WR_WAIT_SOF;
                    end if;
                    
                when WR_WAIT_SOF =>
                    if s_axis_tvalid = '1' and s_axis_tuser = '1' then
                        -- Start of frame detected
                        wr_state <= WR_WRITE_ADDR;
                        wr_x <= (others => '0');
                        wr_y <= (others => '0');
                        wr_addr <= unsigned(buf_base_addr(to_integer(wr_buf)));
                    end if;
                    
                when WR_WRITE_ADDR =>
                    if m_axi_awready = '1' then
                        wr_state <= WR_WRITE_DATA;
                        wr_burst_cnt <= to_unsigned(BURST_LEN - 1, 8);
                    end if;
                    
                when WR_WRITE_DATA =>
                    if m_axi_wready = '1' then
                        if wr_burst_cnt = 0 then
                            wr_state <= WR_WAIT_RESP;
                        else
                            wr_burst_cnt <= wr_burst_cnt - 1;
                        end if;
                        
                        -- Update position
                        if wr_x = unsigned(cfg_frame_width) - 1 then
                            wr_x <= (others => '0');
                            if wr_y = unsigned(cfg_frame_height) - 1 then
                                -- Frame complete
                                wr_y <= (others => '0');
                            else
                                wr_y <= wr_y + 1;
                            end if;
                        else
                            wr_x <= wr_x + 1;
                        end if;
                    end if;
                    
                when WR_WAIT_RESP =>
                    if m_axi_bvalid = '1' then
                        if wr_x = 0 and wr_y = 0 then
                            -- Frame complete, switch buffers
                            wr_state <= WR_WAIT_SOF;
                            ready_buf <= wr_buf;
                            if wr_buf = NUM_BUFFERS - 1 then
                                wr_buf <= (others => '0');
                            else
                                wr_buf <= wr_buf + 1;
                            end if;
                        else
                            -- Continue with next burst
                            wr_state <= WR_WRITE_ADDR;
                            wr_addr <= wr_addr + to_unsigned(BURST_LEN * 8, 32);
                        end if;
                    end if;
                    
                when others =>
                    wr_state <= WR_IDLE;
            end case;
        end if;
    end process;

    -- ==========================================================================
    -- Read State Machine (DDR to CNN)
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_state <= RD_IDLE;
            rd_x <= (others => '0');
            rd_y <= (others => '0');
            rd_addr <= (others => '0');
            rd_burst_cnt <= (others => '0');
            rd_buf <= (others => '0');
        elsif rising_edge(clk) then
            case rd_state is
                when RD_IDLE =>
                    if cfg_enable = '1' and ready_buf /= rd_buf then
                        -- New frame available
                        rd_state <= RD_SEND_SOF;
                        rd_buf <= ready_buf;
                        rd_x <= (others => '0');
                        rd_y <= (others => '0');
                        rd_addr <= unsigned(buf_base_addr(to_integer(ready_buf)));
                    end if;
                    
                when RD_SEND_SOF =>
                    if m_axis_tready = '1' then
                        rd_state <= RD_READ_ADDR;
                    end if;
                    
                when RD_READ_ADDR =>
                    if m_axi_arready = '1' then
                        rd_state <= RD_READ_DATA;
                        rd_burst_cnt <= to_unsigned(BURST_LEN - 1, 8);
                    end if;
                    
                when RD_READ_DATA =>
                    if m_axi_rvalid = '1' then
                        if m_axi_rlast = '1' then
                            rd_state <= RD_OUTPUT;
                        end if;
                    end if;
                    
                when RD_OUTPUT =>
                    if m_axis_tready = '1' then
                        -- Update position
                        if rd_x = unsigned(cfg_frame_width) - 1 then
                            rd_x <= (others => '0');
                            if rd_y = unsigned(cfg_frame_height) - 1 then
                                -- Frame complete
                                rd_state <= RD_IDLE;
                                frame_done <= '1';
                            else
                                rd_y <= rd_y + 1;
                                rd_state <= RD_READ_ADDR;
                                rd_addr <= rd_addr + to_unsigned(BURST_LEN * 8, 32);
                            end if;
                        else
                            rd_x <= rd_x + 1;
                        end if;
                    end if;
                    
                when others =>
                    rd_state <= RD_IDLE;
            end case;
        end if;
    end process;

    -- ==========================================================================
    -- AXI Write Channel Signals
    -- ==========================================================================
    m_axi_awaddr <= std_logic_vector(wr_addr);
    m_axi_awlen <= std_logic_vector(to_unsigned(BURST_LEN - 1, 8));
    m_axi_awsize <= "011";  -- 8 bytes
    m_axi_awburst <= "01";  -- INCR
    m_axi_awvalid <= '1' when wr_state = WR_WRITE_ADDR else '0';
    
    -- Pack pixels into 64-bit word (2 RGB pixels)
    process(clk)
    begin
        if rising_edge(clk) then
            if s_axis_tvalid = '1' and input_ready = '1' then
                wr_fifo_data(23 downto 0) <= s_axis_tdata;
                wr_fifo_data(47 downto 24) <= wr_fifo_data(23 downto 0);
                wr_fifo_data(63 downto 48) <= (others => '0');
            end if;
        end if;
    end process;
    
    m_axi_wdata <= wr_fifo_data;
    m_axi_wstrb <= (others => '1');
    m_axi_wlast <= '1' when wr_burst_cnt = 0 else '0';
    m_axi_wvalid <= '1' when wr_state = WR_WRITE_DATA else '0';
    m_axi_bready <= '1';

    -- ==========================================================================
    -- AXI Read Channel Signals
    -- ==========================================================================
    m_axi_araddr <= std_logic_vector(rd_addr);
    m_axi_arlen <= std_logic_vector(to_unsigned(BURST_LEN - 1, 8));
    m_axi_arsize <= "011";  -- 8 bytes
    m_axi_arburst <= "01";  -- INCR
    m_axi_arvalid <= '1' when rd_state = RD_READ_ADDR else '0';
    m_axi_rready <= '1' when rd_state = RD_READ_DATA else '0';
    
    -- Store read data
    process(clk)
    begin
        if rising_edge(clk) then
            if m_axi_rvalid = '1' and rd_state = RD_READ_DATA then
                rd_fifo_data <= m_axi_rdata;
                rd_fifo_valid <= '1';
            elsif m_axis_tready = '1' then
                rd_fifo_valid <= '0';
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Stream Interface Signals
    -- ==========================================================================
    input_ready <= '1' when (wr_state = WR_WAIT_SOF) or (wr_state = WR_WRITE_DATA and m_axi_wready = '1') else '0';
    s_axis_tready <= input_ready and cfg_enable;
    
    output_valid <= rd_fifo_valid when rd_state = RD_OUTPUT else '0';
    m_axis_tdata <= rd_fifo_data(23 downto 0) when rd_pixel_idx = 0 else rd_fifo_data(47 downto 24);
    m_axis_tvalid <= output_valid;
    m_axis_tlast <= '1' when rd_x = unsigned(cfg_frame_width) - 1 else '0';
    m_axis_tuser <= '1' when rd_state = RD_SEND_SOF else '0';

    -- ==========================================================================
    -- Status Outputs
    -- ==========================================================================
    write_buf_idx <= std_logic_vector(wr_buf);
    read_buf_idx <= std_logic_vector(rd_buf);
    frame_complete <= frame_done;

end rtl;
