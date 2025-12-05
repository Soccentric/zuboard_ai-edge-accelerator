-- =============================================================================
-- CNN Accelerator Top-Level Module
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Complete CNN inference engine with:
--   - AXI-Lite control interface
--   - DMA for weight/bias loading and frame I/O
--   - Configurable Conv2D + Pooling pipeline
--   - Real-time object detection support
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity cnn_accelerator_top is
    generic (
        -- CNN Architecture
        INPUT_WIDTH     : integer := 128;
        INPUT_HEIGHT    : integer := 128;
        INPUT_CHANNELS  : integer := 3;
        NUM_CLASSES     : integer := 10;
        
        -- AXI parameters
        C_S_AXI_DATA_WIDTH  : integer := 32;
        C_S_AXI_ADDR_WIDTH  : integer := 6;
        C_M_AXI_DATA_WIDTH  : integer := 64;
        C_M_AXI_ADDR_WIDTH  : integer := 32
    );
    port (
        -- Clock and Reset
        aclk            : in  std_logic;
        aresetn         : in  std_logic;
        
        -- AXI-Lite Slave Interface (Control/Status)
        s_axi_awaddr    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot    : in  std_logic_vector(2 downto 0);
        s_axi_awvalid   : in  std_logic;
        s_axi_awready   : out std_logic;
        s_axi_wdata     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid    : in  std_logic;
        s_axi_wready    : out std_logic;
        s_axi_bresp     : out std_logic_vector(1 downto 0);
        s_axi_bvalid    : out std_logic;
        s_axi_bready    : in  std_logic;
        s_axi_araddr    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot    : in  std_logic_vector(2 downto 0);
        s_axi_arvalid   : in  std_logic;
        s_axi_arready   : out std_logic;
        s_axi_rdata     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp     : out std_logic_vector(1 downto 0);
        s_axi_rvalid    : out std_logic;
        s_axi_rready    : in  std_logic;
        
        -- AXI-Stream Video Input (from VDMA/Camera)
        s_axis_video_tdata  : in  std_logic_vector(23 downto 0);
        s_axis_video_tvalid : in  std_logic;
        s_axis_video_tready : out std_logic;
        s_axis_video_tlast  : in  std_logic;
        s_axis_video_tuser  : in  std_logic;
        
        -- AXI-Stream Result Output
        m_axis_result_tdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_result_tvalid: out std_logic;
        m_axis_result_tready: in  std_logic;
        m_axis_result_tlast : out std_logic;
        
        -- AXI4 Memory Interface (for weights/feature maps)
        m_axi_awaddr    : out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0);
        m_axi_awlen     : out std_logic_vector(7 downto 0);
        m_axi_awsize    : out std_logic_vector(2 downto 0);
        m_axi_awburst   : out std_logic_vector(1 downto 0);
        m_axi_awvalid   : out std_logic;
        m_axi_awready   : in  std_logic;
        m_axi_wdata     : out std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0);
        m_axi_wstrb     : out std_logic_vector((C_M_AXI_DATA_WIDTH/8)-1 downto 0);
        m_axi_wlast     : out std_logic;
        m_axi_wvalid    : out std_logic;
        m_axi_wready    : in  std_logic;
        m_axi_bresp     : in  std_logic_vector(1 downto 0);
        m_axi_bvalid    : in  std_logic;
        m_axi_bready    : out std_logic;
        m_axi_araddr    : out std_logic_vector(C_M_AXI_ADDR_WIDTH-1 downto 0);
        m_axi_arlen     : out std_logic_vector(7 downto 0);
        m_axi_arsize    : out std_logic_vector(2 downto 0);
        m_axi_arburst   : out std_logic_vector(1 downto 0);
        m_axi_arvalid   : out std_logic;
        m_axi_arready   : in  std_logic;
        m_axi_rdata     : in  std_logic_vector(C_M_AXI_DATA_WIDTH-1 downto 0);
        m_axi_rresp     : in  std_logic_vector(1 downto 0);
        m_axi_rlast     : in  std_logic;
        m_axi_rvalid    : in  std_logic;
        m_axi_rready    : out std_logic;
        
        -- Interrupt
        irq             : out std_logic
    );
end cnn_accelerator_top;

architecture rtl of cnn_accelerator_top is

    -- ==========================================================================
    -- Component Declarations
    -- ==========================================================================
    
    component axi_lite_cnn_ctrl is
        generic (
            C_S_AXI_DATA_WIDTH  : integer := 32;
            C_S_AXI_ADDR_WIDTH  : integer := 6
        );
        port (
            S_AXI_ACLK      : in  std_logic;
            S_AXI_ARESETN   : in  std_logic;
            S_AXI_AWADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_AWPROT    : in  std_logic_vector(2 downto 0);
            S_AXI_AWVALID   : in  std_logic;
            S_AXI_AWREADY   : out std_logic;
            S_AXI_WDATA     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_WSTRB     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
            S_AXI_WVALID    : in  std_logic;
            S_AXI_WREADY    : out std_logic;
            S_AXI_BRESP     : out std_logic_vector(1 downto 0);
            S_AXI_BVALID    : out std_logic;
            S_AXI_BREADY    : in  std_logic;
            S_AXI_ARADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_ARPROT    : in  std_logic_vector(2 downto 0);
            S_AXI_ARVALID   : in  std_logic;
            S_AXI_ARREADY   : out std_logic;
            S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_RRESP     : out std_logic_vector(1 downto 0);
            S_AXI_RVALID    : out std_logic;
            S_AXI_RREADY    : in  std_logic;
            ctrl_start      : out std_logic;
            ctrl_stop       : out std_logic;
            ctrl_reset      : out std_logic;
            stat_busy       : in  std_logic;
            stat_done       : in  std_logic;
            stat_error      : in  std_logic_vector(3 downto 0);
            cfg_layer_enable: out std_logic_vector(7 downto 0);
            cfg_activation  : out std_logic_vector(2 downto 0);
            cfg_pool_type   : out std_logic;
            cfg_input_width : out std_logic_vector(11 downto 0);
            cfg_input_height: out std_logic_vector(11 downto 0);
            dma_weight_addr : out std_logic_vector(31 downto 0);
            dma_bias_addr   : out std_logic_vector(31 downto 0);
            dma_input_addr  : out std_logic_vector(31 downto 0);
            dma_output_addr : out std_logic_vector(31 downto 0);
            irq             : out std_logic;
            perf_cycles     : in  std_logic_vector(31 downto 0);
            perf_ops        : in  std_logic_vector(31 downto 0)
        );
    end component;
    
    component axis_video_input is
        generic (
            INPUT_WIDTH     : integer := 128;
            INPUT_HEIGHT    : integer := 128;
            PIXEL_WIDTH     : integer := 24;
            OUTPUT_WIDTH    : integer := DATA_WIDTH
        );
        port (
            clk             : in  std_logic;
            rst_n           : in  std_logic;
            cfg_enable      : in  std_logic;
            cfg_normalize   : in  std_logic;
            s_axis_tdata    : in  std_logic_vector(PIXEL_WIDTH-1 downto 0);
            s_axis_tvalid   : in  std_logic;
            s_axis_tready   : out std_logic;
            s_axis_tlast    : in  std_logic;
            s_axis_tuser    : in  std_logic;
            m_axis_r_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            m_axis_g_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            m_axis_b_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
            m_axis_tvalid   : out std_logic;
            m_axis_tready   : in  std_logic;
            m_axis_tlast    : out std_logic;
            m_axis_tuser    : out std_logic;
            frame_count     : out std_logic_vector(31 downto 0);
            pixel_count     : out std_logic_vector(31 downto 0)
        );
    end component;
    
    component conv2d_engine is
        generic (
            KERNEL_SIZE     : integer := 3;
            INPUT_CHANNELS  : integer := 3;
            OUTPUT_CHANNELS : integer := 16;
            INPUT_WIDTH     : integer := 128;
            INPUT_HEIGHT    : integer := 128;
            STRIDE          : integer := 1;
            PADDING         : integer := 1;
            NUM_MAC_UNITS   : integer := 9
        );
        port (
            clk             : in  std_logic;
            rst_n           : in  std_logic;
            cfg_enable      : in  std_logic;
            cfg_activation  : in  std_logic_vector(2 downto 0);
            weight_valid    : in  std_logic;
            weight_data     : in  std_logic_vector(WEIGHT_WIDTH-1 downto 0);
            weight_addr     : in  std_logic_vector(15 downto 0);
            weight_filter   : in  std_logic_vector(7 downto 0);
            bias_valid      : in  std_logic;
            bias_data       : in  std_logic_vector(BIAS_WIDTH-1 downto 0);
            bias_addr       : in  std_logic_vector(7 downto 0);
            s_axis_tdata    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            s_axis_tvalid   : in  std_logic;
            s_axis_tready   : out std_logic;
            s_axis_tlast    : in  std_logic;
            s_axis_tuser    : in  std_logic;
            m_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
            m_axis_tvalid   : out std_logic;
            m_axis_tready   : in  std_logic;
            m_axis_tlast    : out std_logic;
            m_axis_tuser    : out std_logic;
            busy            : out std_logic;
            done            : out std_logic
        );
    end component;
    
    component pooling_engine is
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
            cfg_enable      : in  std_logic;
            cfg_pool_type   : in  std_logic;
            s_axis_tdata    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            s_axis_tvalid   : in  std_logic;
            s_axis_tready   : out std_logic;
            s_axis_tlast    : in  std_logic;
            s_axis_tuser    : in  std_logic;
            m_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
            m_axis_tvalid   : out std_logic;
            m_axis_tready   : in  std_logic;
            m_axis_tlast    : out std_logic;
            m_axis_tuser    : out std_logic;
            busy            : out std_logic
        );
    end component;

    -- ==========================================================================
    -- Internal Signals
    -- ==========================================================================
    
    -- Control signals
    signal ctrl_start       : std_logic;
    signal ctrl_stop        : std_logic;
    signal ctrl_reset       : std_logic;
    signal stat_busy        : std_logic;
    signal stat_done        : std_logic;
    signal stat_error       : std_logic_vector(3 downto 0);
    
    -- Configuration signals
    signal cfg_layer_enable : std_logic_vector(7 downto 0);
    signal cfg_activation   : std_logic_vector(2 downto 0);
    signal cfg_pool_type    : std_logic;
    signal cfg_input_width  : std_logic_vector(11 downto 0);
    signal cfg_input_height : std_logic_vector(11 downto 0);
    
    -- DMA addresses
    signal dma_weight_addr  : std_logic_vector(31 downto 0);
    signal dma_bias_addr    : std_logic_vector(31 downto 0);
    signal dma_input_addr   : std_logic_vector(31 downto 0);
    signal dma_output_addr  : std_logic_vector(31 downto 0);
    
    -- Performance counters
    signal perf_cycles      : std_logic_vector(31 downto 0);
    signal perf_ops         : std_logic_vector(31 downto 0);
    signal cycle_counter    : unsigned(31 downto 0);
    signal ops_counter      : unsigned(31 downto 0);
    
    -- Video input signals
    signal video_r, video_g, video_b : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal video_valid      : std_logic;
    signal video_ready      : std_logic;
    signal video_last       : std_logic;
    signal video_user       : std_logic;
    
    -- Conv0 signals (3 input channels -> 16 output channels)
    signal conv0_in_tdata   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal conv0_in_tvalid  : std_logic;
    signal conv0_in_tready  : std_logic;
    signal conv0_in_tlast   : std_logic;
    signal conv0_in_tuser   : std_logic;
    signal conv0_out_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal conv0_out_tvalid : std_logic;
    signal conv0_out_tready : std_logic;
    signal conv0_out_tlast  : std_logic;
    signal conv0_out_tuser  : std_logic;
    signal conv0_busy       : std_logic;
    signal conv0_done       : std_logic;
    
    -- Pool0 signals
    signal pool0_out_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal pool0_out_tvalid : std_logic;
    signal pool0_out_tready : std_logic;
    signal pool0_out_tlast  : std_logic;
    signal pool0_out_tuser  : std_logic;
    signal pool0_busy       : std_logic;
    
    -- Conv1 signals (16 input channels -> 32 output channels)
    signal conv1_out_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal conv1_out_tvalid : std_logic;
    signal conv1_out_tready : std_logic;
    signal conv1_out_tlast  : std_logic;
    signal conv1_out_tuser  : std_logic;
    signal conv1_busy       : std_logic;
    signal conv1_done       : std_logic;
    
    -- Pool1 signals
    signal pool1_out_tdata  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal pool1_out_tvalid : std_logic;
    signal pool1_out_tready : std_logic;
    signal pool1_out_tlast  : std_logic;
    signal pool1_out_tuser  : std_logic;
    signal pool1_busy       : std_logic;
    
    -- Weight/bias loading
    signal weight_valid     : std_logic;
    signal weight_data      : std_logic_vector(WEIGHT_WIDTH-1 downto 0);
    signal weight_addr      : std_logic_vector(15 downto 0);
    signal weight_filter    : std_logic_vector(7 downto 0);
    signal bias_valid       : std_logic;
    signal bias_data        : std_logic_vector(BIAS_WIDTH-1 downto 0);
    signal bias_addr        : std_logic_vector(7 downto 0);
    
    -- Channel multiplexer for RGB input
    signal channel_sel      : unsigned(1 downto 0);
    signal channel_data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Global enable
    signal global_enable    : std_logic;
    
    -- FSM for overall control
    type main_state_t is (IDLE, LOAD_WEIGHTS, PROCESS_FRAME, OUTPUT_RESULT, DONE);
    signal main_state       : main_state_t;

begin

    -- ==========================================================================
    -- AXI-Lite Control Interface
    -- ==========================================================================
    ctrl_inst : axi_lite_cnn_ctrl
        generic map (
            C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
        )
        port map (
            S_AXI_ACLK      => aclk,
            S_AXI_ARESETN   => aresetn,
            S_AXI_AWADDR    => s_axi_awaddr,
            S_AXI_AWPROT    => s_axi_awprot,
            S_AXI_AWVALID   => s_axi_awvalid,
            S_AXI_AWREADY   => s_axi_awready,
            S_AXI_WDATA     => s_axi_wdata,
            S_AXI_WSTRB     => s_axi_wstrb,
            S_AXI_WVALID    => s_axi_wvalid,
            S_AXI_WREADY    => s_axi_wready,
            S_AXI_BRESP     => s_axi_bresp,
            S_AXI_BVALID    => s_axi_bvalid,
            S_AXI_BREADY    => s_axi_bready,
            S_AXI_ARADDR    => s_axi_araddr,
            S_AXI_ARPROT    => s_axi_arprot,
            S_AXI_ARVALID   => s_axi_arvalid,
            S_AXI_ARREADY   => s_axi_arready,
            S_AXI_RDATA     => s_axi_rdata,
            S_AXI_RRESP     => s_axi_rresp,
            S_AXI_RVALID    => s_axi_rvalid,
            S_AXI_RREADY    => s_axi_rready,
            ctrl_start      => ctrl_start,
            ctrl_stop       => ctrl_stop,
            ctrl_reset      => ctrl_reset,
            stat_busy       => stat_busy,
            stat_done       => stat_done,
            stat_error      => stat_error,
            cfg_layer_enable => cfg_layer_enable,
            cfg_activation  => cfg_activation,
            cfg_pool_type   => cfg_pool_type,
            cfg_input_width => cfg_input_width,
            cfg_input_height => cfg_input_height,
            dma_weight_addr => dma_weight_addr,
            dma_bias_addr   => dma_bias_addr,
            dma_input_addr  => dma_input_addr,
            dma_output_addr => dma_output_addr,
            irq             => irq,
            perf_cycles     => perf_cycles,
            perf_ops        => perf_ops
        );

    -- ==========================================================================
    -- Video Input Processing
    -- ==========================================================================
    video_input_inst : axis_video_input
        generic map (
            INPUT_WIDTH  => INPUT_WIDTH,
            INPUT_HEIGHT => INPUT_HEIGHT,
            PIXEL_WIDTH  => 24,
            OUTPUT_WIDTH => DATA_WIDTH
        )
        port map (
            clk             => aclk,
            rst_n           => aresetn,
            cfg_enable      => global_enable,
            cfg_normalize   => '1',  -- Normalize to [-1, 1]
            s_axis_tdata    => s_axis_video_tdata,
            s_axis_tvalid   => s_axis_video_tvalid,
            s_axis_tready   => s_axis_video_tready,
            s_axis_tlast    => s_axis_video_tlast,
            s_axis_tuser    => s_axis_video_tuser,
            m_axis_r_tdata  => video_r,
            m_axis_g_tdata  => video_g,
            m_axis_b_tdata  => video_b,
            m_axis_tvalid   => video_valid,
            m_axis_tready   => video_ready,
            m_axis_tlast    => video_last,
            m_axis_tuser    => video_user,
            frame_count     => open,
            pixel_count     => open
        );

    -- ==========================================================================
    -- RGB Channel Serializer (R, G, B -> sequential)
    -- ==========================================================================
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            channel_sel <= (others => '0');
        elsif rising_edge(aclk) then
            if video_valid = '1' and conv0_in_tready = '1' then
                if channel_sel = 2 then
                    channel_sel <= (others => '0');
                else
                    channel_sel <= channel_sel + 1;
                end if;
            end if;
        end if;
    end process;
    
    channel_data <= video_r when channel_sel = 0 else
                    video_g when channel_sel = 1 else
                    video_b;
    
    conv0_in_tdata <= channel_data;
    conv0_in_tvalid <= video_valid and global_enable;
    conv0_in_tlast <= video_last when channel_sel = 2 else '0';
    conv0_in_tuser <= video_user when channel_sel = 0 else '0';
    video_ready <= conv0_in_tready when channel_sel = 2 else '1';

    -- ==========================================================================
    -- Conv Layer 0: 3 channels -> 16 filters, 3x3 kernel
    -- ==========================================================================
    conv0_inst : conv2d_engine
        generic map (
            KERNEL_SIZE     => 3,
            INPUT_CHANNELS  => 3,
            OUTPUT_CHANNELS => 16,
            INPUT_WIDTH     => INPUT_WIDTH,
            INPUT_HEIGHT    => INPUT_HEIGHT,
            STRIDE          => 1,
            PADDING         => 1,
            NUM_MAC_UNITS   => 9
        )
        port map (
            clk             => aclk,
            rst_n           => aresetn,
            cfg_enable      => cfg_layer_enable(0),
            cfg_activation  => cfg_activation,
            weight_valid    => weight_valid,
            weight_data     => weight_data,
            weight_addr     => weight_addr,
            weight_filter   => weight_filter,
            bias_valid      => bias_valid,
            bias_data       => bias_data,
            bias_addr       => bias_addr,
            s_axis_tdata    => conv0_in_tdata,
            s_axis_tvalid   => conv0_in_tvalid,
            s_axis_tready   => conv0_in_tready,
            s_axis_tlast    => conv0_in_tlast,
            s_axis_tuser    => conv0_in_tuser,
            m_axis_tdata    => conv0_out_tdata,
            m_axis_tvalid   => conv0_out_tvalid,
            m_axis_tready   => conv0_out_tready,
            m_axis_tlast    => conv0_out_tlast,
            m_axis_tuser    => conv0_out_tuser,
            busy            => conv0_busy,
            done            => conv0_done
        );

    -- ==========================================================================
    -- Pooling Layer 0: 2x2 Max Pooling
    -- ==========================================================================
    pool0_inst : pooling_engine
        generic map (
            POOL_SIZE       => 2,
            INPUT_WIDTH     => INPUT_WIDTH,
            INPUT_HEIGHT    => INPUT_HEIGHT,
            INPUT_CHANNELS  => 16,
            STRIDE          => 2
        )
        port map (
            clk             => aclk,
            rst_n           => aresetn,
            cfg_enable      => cfg_layer_enable(1),
            cfg_pool_type   => cfg_pool_type,
            s_axis_tdata    => conv0_out_tdata,
            s_axis_tvalid   => conv0_out_tvalid,
            s_axis_tready   => conv0_out_tready,
            s_axis_tlast    => conv0_out_tlast,
            s_axis_tuser    => conv0_out_tuser,
            m_axis_tdata    => pool0_out_tdata,
            m_axis_tvalid   => pool0_out_tvalid,
            m_axis_tready   => pool0_out_tready,
            m_axis_tlast    => pool0_out_tlast,
            m_axis_tuser    => pool0_out_tuser,
            busy            => pool0_busy
        );

    -- ==========================================================================
    -- Conv Layer 1: 16 channels -> 32 filters, 3x3 kernel
    -- ==========================================================================
    conv1_inst : conv2d_engine
        generic map (
            KERNEL_SIZE     => 3,
            INPUT_CHANNELS  => 16,
            OUTPUT_CHANNELS => 32,
            INPUT_WIDTH     => INPUT_WIDTH/2,
            INPUT_HEIGHT    => INPUT_HEIGHT/2,
            STRIDE          => 1,
            PADDING         => 1,
            NUM_MAC_UNITS   => 9
        )
        port map (
            clk             => aclk,
            rst_n           => aresetn,
            cfg_enable      => cfg_layer_enable(2),
            cfg_activation  => cfg_activation,
            weight_valid    => weight_valid,
            weight_data     => weight_data,
            weight_addr     => weight_addr,
            weight_filter   => weight_filter,
            bias_valid      => bias_valid,
            bias_data       => bias_data,
            bias_addr       => bias_addr,
            s_axis_tdata    => pool0_out_tdata,
            s_axis_tvalid   => pool0_out_tvalid,
            s_axis_tready   => pool0_out_tready,
            s_axis_tlast    => pool0_out_tlast,
            s_axis_tuser    => pool0_out_tuser,
            m_axis_tdata    => conv1_out_tdata,
            m_axis_tvalid   => conv1_out_tvalid,
            m_axis_tready   => conv1_out_tready,
            m_axis_tlast    => conv1_out_tlast,
            m_axis_tuser    => conv1_out_tuser,
            busy            => conv1_busy,
            done            => conv1_done
        );

    -- ==========================================================================
    -- Pooling Layer 1: 2x2 Max Pooling
    -- ==========================================================================
    pool1_inst : pooling_engine
        generic map (
            POOL_SIZE       => 2,
            INPUT_WIDTH     => INPUT_WIDTH/2,
            INPUT_HEIGHT    => INPUT_HEIGHT/2,
            INPUT_CHANNELS  => 32,
            STRIDE          => 2
        )
        port map (
            clk             => aclk,
            rst_n           => aresetn,
            cfg_enable      => cfg_layer_enable(3),
            cfg_pool_type   => cfg_pool_type,
            s_axis_tdata    => conv1_out_tdata,
            s_axis_tvalid   => conv1_out_tvalid,
            s_axis_tready   => conv1_out_tready,
            s_axis_tlast    => conv1_out_tlast,
            s_axis_tuser    => conv1_out_tuser,
            m_axis_tdata    => pool1_out_tdata,
            m_axis_tvalid   => pool1_out_tvalid,
            m_axis_tready   => pool1_out_tready,
            m_axis_tlast    => pool1_out_tlast,
            m_axis_tuser    => pool1_out_tuser,
            busy            => pool1_busy
        );

    -- ==========================================================================
    -- Output to Result Stream
    -- ==========================================================================
    m_axis_result_tdata <= pool1_out_tdata;
    m_axis_result_tvalid <= pool1_out_tvalid;
    pool1_out_tready <= m_axis_result_tready;
    m_axis_result_tlast <= pool1_out_tlast;

    -- ==========================================================================
    -- Main Control FSM
    -- ==========================================================================
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            main_state <= IDLE;
            global_enable <= '0';
            stat_busy <= '0';
            stat_done <= '0';
            stat_error <= (others => '0');
        elsif rising_edge(aclk) then
            if ctrl_reset = '1' then
                main_state <= IDLE;
                global_enable <= '0';
                stat_busy <= '0';
                stat_done <= '0';
            else
                case main_state is
                    when IDLE =>
                        stat_done <= '0';
                        if ctrl_start = '1' then
                            main_state <= LOAD_WEIGHTS;
                            stat_busy <= '1';
                        end if;
                        
                    when LOAD_WEIGHTS =>
                        -- Weight loading handled by DMA
                        -- Simplified: assume weights are pre-loaded
                        main_state <= PROCESS_FRAME;
                        global_enable <= '1';
                        
                    when PROCESS_FRAME =>
                        if ctrl_stop = '1' then
                            main_state <= IDLE;
                            global_enable <= '0';
                            stat_busy <= '0';
                        elsif conv1_done = '1' then
                            main_state <= OUTPUT_RESULT;
                        end if;
                        
                    when OUTPUT_RESULT =>
                        if pool1_out_tlast = '1' and pool1_out_tvalid = '1' and m_axis_result_tready = '1' then
                            main_state <= DONE;
                        end if;
                        
                    when DONE =>
                        stat_done <= '1';
                        stat_busy <= '0';
                        global_enable <= '0';
                        main_state <= IDLE;
                        
                    when others =>
                        main_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Performance Counters
    -- ==========================================================================
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            cycle_counter <= (others => '0');
            ops_counter <= (others => '0');
        elsif rising_edge(aclk) then
            if ctrl_reset = '1' or ctrl_start = '1' then
                cycle_counter <= (others => '0');
                ops_counter <= (others => '0');
            elsif stat_busy = '1' then
                cycle_counter <= cycle_counter + 1;
                -- Count MAC operations
                if conv0_out_tvalid = '1' or conv1_out_tvalid = '1' then
                    ops_counter <= ops_counter + 9;  -- 3x3 kernel = 9 MACs
                end if;
            end if;
        end if;
    end process;
    
    perf_cycles <= std_logic_vector(cycle_counter);
    perf_ops <= std_logic_vector(ops_counter);

    -- ==========================================================================
    -- AXI Memory Interface (simplified - directly pass through)
    -- ==========================================================================
    -- In a full implementation, this would have a DMA engine for weight loading
    m_axi_awaddr <= dma_weight_addr;
    m_axi_awlen <= x"0F";
    m_axi_awsize <= "011";
    m_axi_awburst <= "01";
    m_axi_awvalid <= '0';  -- Not used in this simplified version
    m_axi_wdata <= (others => '0');
    m_axi_wstrb <= (others => '0');
    m_axi_wlast <= '0';
    m_axi_wvalid <= '0';
    m_axi_bready <= '1';
    m_axi_araddr <= dma_input_addr;
    m_axi_arlen <= x"0F";
    m_axi_arsize <= "011";
    m_axi_arburst <= "01";
    m_axi_arvalid <= '0';
    m_axi_rready <= '1';
    
    -- Weight/bias loading (simplified - would be driven by DMA in full implementation)
    weight_valid <= '0';
    weight_data <= (others => '0');
    weight_addr <= (others => '0');
    weight_filter <= (others => '0');
    bias_valid <= '0';
    bias_data <= (others => '0');
    bias_addr <= (others => '0');

end rtl;
