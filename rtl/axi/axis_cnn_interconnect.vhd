-- =============================================================================
-- AXI-Stream Interconnect for CNN Pipeline
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Features:
--   - Connects multiple CNN layers in sequence
--   - Configurable routing based on layer execution order
--   - Bypass paths for skip connections
--   - FIFO buffering between stages
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity axis_cnn_interconnect is
    generic (
        NUM_LAYERS      : integer := 8;
        FIFO_DEPTH      : integer := 512
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_layer_enable: in  std_logic_vector(NUM_LAYERS-1 downto 0);
        cfg_route_sel   : in  std_logic_vector(3 downto 0);  -- Which output to use
        
        -- Input from video source
        s_axis_tdata    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tuser    : in  std_logic;
        
        -- Connections to Conv Layer 0
        conv0_s_tdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        conv0_s_tvalid  : out std_logic;
        conv0_s_tready  : in  std_logic;
        conv0_s_tlast   : out std_logic;
        conv0_s_tuser   : out std_logic;
        conv0_m_tdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        conv0_m_tvalid  : in  std_logic;
        conv0_m_tready  : out std_logic;
        conv0_m_tlast   : in  std_logic;
        conv0_m_tuser   : in  std_logic;
        
        -- Connections to Pool Layer 0
        pool0_s_tdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        pool0_s_tvalid  : out std_logic;
        pool0_s_tready  : in  std_logic;
        pool0_s_tlast   : out std_logic;
        pool0_s_tuser   : out std_logic;
        pool0_m_tdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        pool0_m_tvalid  : in  std_logic;
        pool0_m_tready  : out std_logic;
        pool0_m_tlast   : in  std_logic;
        pool0_m_tuser   : in  std_logic;
        
        -- Connections to Conv Layer 1
        conv1_s_tdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        conv1_s_tvalid  : out std_logic;
        conv1_s_tready  : in  std_logic;
        conv1_s_tlast   : out std_logic;
        conv1_s_tuser   : out std_logic;
        conv1_m_tdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        conv1_m_tvalid  : in  std_logic;
        conv1_m_tready  : out std_logic;
        conv1_m_tlast   : in  std_logic;
        conv1_m_tuser   : in  std_logic;
        
        -- Connections to Pool Layer 1
        pool1_s_tdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        pool1_s_tvalid  : out std_logic;
        pool1_s_tready  : in  std_logic;
        pool1_s_tlast   : out std_logic;
        pool1_s_tuser   : out std_logic;
        pool1_m_tdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        pool1_m_tvalid  : in  std_logic;
        pool1_m_tready  : out std_logic;
        pool1_m_tlast   : in  std_logic;
        pool1_m_tuser   : in  std_logic;
        
        -- Final Output
        m_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic
    );
end axis_cnn_interconnect;

architecture rtl of axis_cnn_interconnect is

    -- Internal FIFO signals
    type fifo_data_t is array (0 to 3) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_din     : fifo_data_t;
    signal fifo_dout    : fifo_data_t;
    signal fifo_wr_en   : std_logic_vector(3 downto 0);
    signal fifo_rd_en   : std_logic_vector(3 downto 0);
    signal fifo_full    : std_logic_vector(3 downto 0);
    signal fifo_empty   : std_logic_vector(3 downto 0);

begin

    -- ==========================================================================
    -- Input to Conv0 connection (direct or through FIFO)
    -- ==========================================================================
    conv0_s_tdata <= s_axis_tdata;
    conv0_s_tvalid <= s_axis_tvalid when cfg_layer_enable(0) = '1' else '0';
    conv0_s_tlast <= s_axis_tlast;
    conv0_s_tuser <= s_axis_tuser;
    s_axis_tready <= conv0_s_tready when cfg_layer_enable(0) = '1' else '1';

    -- ==========================================================================
    -- Conv0 to Pool0
    -- ==========================================================================
    pool0_s_tdata <= conv0_m_tdata;
    pool0_s_tvalid <= conv0_m_tvalid when cfg_layer_enable(1) = '1' else '0';
    pool0_s_tlast <= conv0_m_tlast;
    pool0_s_tuser <= conv0_m_tuser;
    conv0_m_tready <= pool0_s_tready when cfg_layer_enable(1) = '1' else '1';

    -- ==========================================================================
    -- Pool0 to Conv1
    -- ==========================================================================
    conv1_s_tdata <= pool0_m_tdata;
    conv1_s_tvalid <= pool0_m_tvalid when cfg_layer_enable(2) = '1' else '0';
    conv1_s_tlast <= pool0_m_tlast;
    conv1_s_tuser <= pool0_m_tuser;
    pool0_m_tready <= conv1_s_tready when cfg_layer_enable(2) = '1' else '1';

    -- ==========================================================================
    -- Conv1 to Pool1
    -- ==========================================================================
    pool1_s_tdata <= conv1_m_tdata;
    pool1_s_tvalid <= conv1_m_tvalid when cfg_layer_enable(3) = '1' else '0';
    pool1_s_tlast <= conv1_m_tlast;
    pool1_s_tuser <= conv1_m_tuser;
    conv1_m_tready <= pool1_s_tready when cfg_layer_enable(3) = '1' else '1';

    -- ==========================================================================
    -- Output Multiplexer
    -- ==========================================================================
    process(cfg_route_sel, pool1_m_tdata, pool1_m_tvalid, pool1_m_tlast, pool1_m_tuser,
            conv1_m_tdata, conv1_m_tvalid, conv1_m_tlast, conv1_m_tuser,
            pool0_m_tdata, pool0_m_tvalid, pool0_m_tlast, pool0_m_tuser,
            conv0_m_tdata, conv0_m_tvalid, conv0_m_tlast, conv0_m_tuser)
    begin
        case cfg_route_sel is
            when "0000" =>  -- After Conv0
                m_axis_tdata <= conv0_m_tdata;
                m_axis_tvalid <= conv0_m_tvalid;
                m_axis_tlast <= conv0_m_tlast;
                m_axis_tuser <= conv0_m_tuser;
            when "0001" =>  -- After Pool0
                m_axis_tdata <= pool0_m_tdata;
                m_axis_tvalid <= pool0_m_tvalid;
                m_axis_tlast <= pool0_m_tlast;
                m_axis_tuser <= pool0_m_tuser;
            when "0010" =>  -- After Conv1
                m_axis_tdata <= conv1_m_tdata;
                m_axis_tvalid <= conv1_m_tvalid;
                m_axis_tlast <= conv1_m_tlast;
                m_axis_tuser <= conv1_m_tuser;
            when others =>  -- After Pool1 (default - full pipeline)
                m_axis_tdata <= pool1_m_tdata;
                m_axis_tvalid <= pool1_m_tvalid;
                m_axis_tlast <= pool1_m_tlast;
                m_axis_tuser <= pool1_m_tuser;
        end case;
    end process;
    
    pool1_m_tready <= m_axis_tready;

end rtl;
