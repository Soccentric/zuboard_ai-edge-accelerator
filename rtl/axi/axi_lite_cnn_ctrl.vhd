-- =============================================================================
-- AXI-Lite Register Interface for CNN Accelerator Control
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Register Map:
--   0x00: Control Register (start, stop, reset)
--   0x04: Status Register (busy, done, error)
--   0x08: Configuration (layer enables, activation type)
--   0x0C: Input dimensions (width, height)
--   0x10: Weight base address
--   0x14: Bias base address
--   0x18: Input frame base address
--   0x1C: Output result base address
--   0x20: Interrupt enable
--   0x24: Interrupt status
--   0x28: Performance counter (cycles)
--   0x2C: Performance counter (operations)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_lite_cnn_ctrl is
    generic (
        C_S_AXI_DATA_WIDTH  : integer := 32;
        C_S_AXI_ADDR_WIDTH  : integer := 6
    );
    port (
        -- AXI-Lite Slave Interface
        S_AXI_ACLK      : in  std_logic;
        S_AXI_ARESETN   : in  std_logic;
        
        -- Write address channel
        S_AXI_AWADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_AWPROT    : in  std_logic_vector(2 downto 0);
        S_AXI_AWVALID   : in  std_logic;
        S_AXI_AWREADY   : out std_logic;
        
        -- Write data channel
        S_AXI_WDATA     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_WSTRB     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        S_AXI_WVALID    : in  std_logic;
        S_AXI_WREADY    : out std_logic;
        
        -- Write response channel
        S_AXI_BRESP     : out std_logic_vector(1 downto 0);
        S_AXI_BVALID    : out std_logic;
        S_AXI_BREADY    : in  std_logic;
        
        -- Read address channel
        S_AXI_ARADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_ARPROT    : in  std_logic_vector(2 downto 0);
        S_AXI_ARVALID   : in  std_logic;
        S_AXI_ARREADY   : out std_logic;
        
        -- Read data channel
        S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_RRESP     : out std_logic_vector(1 downto 0);
        S_AXI_RVALID    : out std_logic;
        S_AXI_RREADY    : in  std_logic;
        
        -- CNN Control Interface
        ctrl_start      : out std_logic;
        ctrl_stop       : out std_logic;
        ctrl_reset      : out std_logic;
        
        -- CNN Status Interface
        stat_busy       : in  std_logic;
        stat_done       : in  std_logic;
        stat_error      : in  std_logic_vector(3 downto 0);
        
        -- CNN Configuration
        cfg_layer_enable: out std_logic_vector(7 downto 0);
        cfg_activation  : out std_logic_vector(2 downto 0);
        cfg_pool_type   : out std_logic;
        cfg_input_width : out std_logic_vector(11 downto 0);
        cfg_input_height: out std_logic_vector(11 downto 0);
        
        -- DMA Addresses
        dma_weight_addr : out std_logic_vector(31 downto 0);
        dma_bias_addr   : out std_logic_vector(31 downto 0);
        dma_input_addr  : out std_logic_vector(31 downto 0);
        dma_output_addr : out std_logic_vector(31 downto 0);
        
        -- Interrupt
        irq             : out std_logic;
        
        -- Performance counters input
        perf_cycles     : in  std_logic_vector(31 downto 0);
        perf_ops        : in  std_logic_vector(31 downto 0)
    );
end axi_lite_cnn_ctrl;

architecture rtl of axi_lite_cnn_ctrl is

    -- AXI-Lite state machine
    type axi_state_t is (IDLE, WRITE_ADDR, WRITE_DATA, WRITE_RESP, READ_ADDR, READ_DATA);
    signal axi_state : axi_state_t;
    
    -- Register addresses
    constant REG_CONTROL        : std_logic_vector(5 downto 0) := "000000";  -- 0x00
    constant REG_STATUS         : std_logic_vector(5 downto 0) := "000100";  -- 0x04
    constant REG_CONFIG         : std_logic_vector(5 downto 0) := "001000";  -- 0x08
    constant REG_INPUT_DIM      : std_logic_vector(5 downto 0) := "001100";  -- 0x0C
    constant REG_WEIGHT_ADDR    : std_logic_vector(5 downto 0) := "010000";  -- 0x10
    constant REG_BIAS_ADDR      : std_logic_vector(5 downto 0) := "010100";  -- 0x14
    constant REG_INPUT_ADDR     : std_logic_vector(5 downto 0) := "011000";  -- 0x18
    constant REG_OUTPUT_ADDR    : std_logic_vector(5 downto 0) := "011100";  -- 0x1C
    constant REG_IRQ_ENABLE     : std_logic_vector(5 downto 0) := "100000";  -- 0x20
    constant REG_IRQ_STATUS     : std_logic_vector(5 downto 0) := "100100";  -- 0x24
    constant REG_PERF_CYCLES    : std_logic_vector(5 downto 0) := "101000";  -- 0x28
    constant REG_PERF_OPS       : std_logic_vector(5 downto 0) := "101100";  -- 0x2C
    
    -- Registers
    signal reg_control      : std_logic_vector(31 downto 0);
    signal reg_config       : std_logic_vector(31 downto 0);
    signal reg_input_dim    : std_logic_vector(31 downto 0);
    signal reg_weight_addr  : std_logic_vector(31 downto 0);
    signal reg_bias_addr    : std_logic_vector(31 downto 0);
    signal reg_input_addr   : std_logic_vector(31 downto 0);
    signal reg_output_addr  : std_logic_vector(31 downto 0);
    signal reg_irq_enable   : std_logic_vector(31 downto 0);
    signal reg_irq_status   : std_logic_vector(31 downto 0);
    
    -- Internal signals
    signal awaddr_reg       : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal araddr_reg       : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal rdata_reg        : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    
    -- Pulse generators for control bits
    signal start_pulse      : std_logic;
    signal stop_pulse       : std_logic;
    signal reset_pulse      : std_logic;
    signal control_prev     : std_logic_vector(2 downto 0);
    
    -- Done edge detection for interrupt
    signal done_prev        : std_logic;
    signal done_edge        : std_logic;

begin

    -- ==========================================================================
    -- AXI-Lite State Machine
    -- ==========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                axi_state <= IDLE;
                awaddr_reg <= (others => '0');
                araddr_reg <= (others => '0');
            else
                case axi_state is
                    when IDLE =>
                        if S_AXI_AWVALID = '1' then
                            axi_state <= WRITE_ADDR;
                            awaddr_reg <= S_AXI_AWADDR;
                        elsif S_AXI_ARVALID = '1' then
                            axi_state <= READ_ADDR;
                            araddr_reg <= S_AXI_ARADDR;
                        end if;
                        
                    when WRITE_ADDR =>
                        if S_AXI_WVALID = '1' then
                            axi_state <= WRITE_RESP;
                        end if;
                        
                    when WRITE_RESP =>
                        if S_AXI_BREADY = '1' then
                            axi_state <= IDLE;
                        end if;
                        
                    when READ_ADDR =>
                        axi_state <= READ_DATA;
                        
                    when READ_DATA =>
                        if S_AXI_RREADY = '1' then
                            axi_state <= IDLE;
                        end if;
                        
                    when others =>
                        axi_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Write Process
    -- ==========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                reg_control <= (others => '0');
                reg_config <= x"000001FF";  -- All layers enabled, ReLU activation
                reg_input_dim <= x"00800080";  -- 128x128
                reg_weight_addr <= (others => '0');
                reg_bias_addr <= (others => '0');
                reg_input_addr <= (others => '0');
                reg_output_addr <= (others => '0');
                reg_irq_enable <= (others => '0');
            elsif axi_state = WRITE_ADDR and S_AXI_WVALID = '1' then
                case awaddr_reg is
                    when REG_CONTROL =>
                        reg_control <= S_AXI_WDATA;
                    when REG_CONFIG =>
                        reg_config <= S_AXI_WDATA;
                    when REG_INPUT_DIM =>
                        reg_input_dim <= S_AXI_WDATA;
                    when REG_WEIGHT_ADDR =>
                        reg_weight_addr <= S_AXI_WDATA;
                    when REG_BIAS_ADDR =>
                        reg_bias_addr <= S_AXI_WDATA;
                    when REG_INPUT_ADDR =>
                        reg_input_addr <= S_AXI_WDATA;
                    when REG_OUTPUT_ADDR =>
                        reg_output_addr <= S_AXI_WDATA;
                    when REG_IRQ_ENABLE =>
                        reg_irq_enable <= S_AXI_WDATA;
                    when REG_IRQ_STATUS =>
                        -- Write 1 to clear
                        reg_irq_status <= reg_irq_status and not S_AXI_WDATA;
                    when others =>
                        null;
                end case;
            else
                -- Auto-clear control pulses
                reg_control(2 downto 0) <= (others => '0');
                
                -- Set interrupt status on done edge
                if done_edge = '1' then
                    reg_irq_status(0) <= '1';
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Read Process
    -- ==========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if axi_state = READ_ADDR then
                case araddr_reg is
                    when REG_CONTROL =>
                        rdata_reg <= reg_control;
                    when REG_STATUS =>
                        rdata_reg <= (31 downto 8 => '0') & stat_error & "00" & stat_done & stat_busy;
                    when REG_CONFIG =>
                        rdata_reg <= reg_config;
                    when REG_INPUT_DIM =>
                        rdata_reg <= reg_input_dim;
                    when REG_WEIGHT_ADDR =>
                        rdata_reg <= reg_weight_addr;
                    when REG_BIAS_ADDR =>
                        rdata_reg <= reg_bias_addr;
                    when REG_INPUT_ADDR =>
                        rdata_reg <= reg_input_addr;
                    when REG_OUTPUT_ADDR =>
                        rdata_reg <= reg_output_addr;
                    when REG_IRQ_ENABLE =>
                        rdata_reg <= reg_irq_enable;
                    when REG_IRQ_STATUS =>
                        rdata_reg <= reg_irq_status;
                    when REG_PERF_CYCLES =>
                        rdata_reg <= perf_cycles;
                    when REG_PERF_OPS =>
                        rdata_reg <= perf_ops;
                    when others =>
                        rdata_reg <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Control Pulse Generation
    -- ==========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                control_prev <= (others => '0');
                done_prev <= '0';
            else
                control_prev <= reg_control(2 downto 0);
                done_prev <= stat_done;
            end if;
        end if;
    end process;
    
    start_pulse <= reg_control(0) and not control_prev(0);
    stop_pulse <= reg_control(1) and not control_prev(1);
    reset_pulse <= reg_control(2) and not control_prev(2);
    done_edge <= stat_done and not done_prev;

    -- ==========================================================================
    -- AXI-Lite Response Signals
    -- ==========================================================================
    S_AXI_AWREADY <= '1' when axi_state = IDLE else '0';
    S_AXI_WREADY <= '1' when axi_state = WRITE_ADDR else '0';
    S_AXI_BRESP <= "00";  -- OKAY
    S_AXI_BVALID <= '1' when axi_state = WRITE_RESP else '0';
    S_AXI_ARREADY <= '1' when axi_state = IDLE else '0';
    S_AXI_RDATA <= rdata_reg;
    S_AXI_RRESP <= "00";  -- OKAY
    S_AXI_RVALID <= '1' when axi_state = READ_DATA else '0';

    -- ==========================================================================
    -- Output Mapping
    -- ==========================================================================
    ctrl_start <= start_pulse;
    ctrl_stop <= stop_pulse;
    ctrl_reset <= reset_pulse;
    
    cfg_layer_enable <= reg_config(7 downto 0);
    cfg_activation <= reg_config(10 downto 8);
    cfg_pool_type <= reg_config(11);
    cfg_input_width <= reg_input_dim(11 downto 0);
    cfg_input_height <= reg_input_dim(27 downto 16);
    
    dma_weight_addr <= reg_weight_addr;
    dma_bias_addr <= reg_bias_addr;
    dma_input_addr <= reg_input_addr;
    dma_output_addr <= reg_output_addr;
    
    irq <= '1' when (reg_irq_status and reg_irq_enable) /= x"00000000" else '0';

end rtl;
