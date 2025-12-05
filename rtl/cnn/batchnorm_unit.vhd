-- =============================================================================
-- Batch Normalization Unit
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Implements: y = gamma * (x - mean) / sqrt(variance + epsilon) + beta
-- Simplified for inference: y = scale * x + bias (pre-computed parameters)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity batchnorm_unit is
    generic (
        NUM_CHANNELS    : integer := 64
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_enable      : in  std_logic;
        
        -- Parameter loading
        param_valid     : in  std_logic;
        param_channel   : in  std_logic_vector(9 downto 0);
        param_scale     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        param_bias      : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Channel index for processing
        channel_idx     : in  std_logic_vector(9 downto 0);
        
        -- Input
        data_in         : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_in        : in  std_logic;
        
        -- Output
        data_out        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_out       : out std_logic
    );
end batchnorm_unit;

architecture rtl of batchnorm_unit is

    -- Parameter storage
    type param_array_t is array (0 to NUM_CHANNELS-1) of pixel_t;
    signal scale_mem    : param_array_t;
    signal bias_mem     : param_array_t;
    
    -- Pipeline registers
    signal input_d      : pixel_t;
    signal scale_d      : pixel_t;
    signal bias_d       : pixel_t;
    signal valid_d      : std_logic_vector(2 downto 0);
    
    -- Computation
    signal product      : signed(2*DATA_WIDTH-1 downto 0);
    signal scaled       : pixel_t;
    signal result       : pixel_t;

begin

    -- ==========================================================================
    -- Parameter Memory
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if param_valid = '1' then
                if to_integer(unsigned(param_channel)) < NUM_CHANNELS then
                    scale_mem(to_integer(unsigned(param_channel))) <= signed(param_scale);
                    bias_mem(to_integer(unsigned(param_channel))) <= signed(param_bias);
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Pipeline Stage 1: Read parameters and latch input
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            input_d <= (others => '0');
            scale_d <= (others => '0');
            bias_d <= (others => '0');
            valid_d <= (others => '0');
        elsif rising_edge(clk) then
            valid_d(0) <= valid_in and cfg_enable;
            valid_d(2 downto 1) <= valid_d(1 downto 0);
            
            input_d <= signed(data_in);
            
            if to_integer(unsigned(channel_idx)) < NUM_CHANNELS then
                scale_d <= scale_mem(to_integer(unsigned(channel_idx)));
                bias_d <= bias_mem(to_integer(unsigned(channel_idx)));
            else
                scale_d <= to_signed(256, DATA_WIDTH);  -- 1.0 in Q8.8
                bias_d <= (others => '0');
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Pipeline Stage 2: Multiply
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            product <= input_d * scale_d;
        end if;
    end process;
    
    -- Scale back from Q16.16 to Q8.8
    scaled <= product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);

    -- ==========================================================================
    -- Pipeline Stage 3: Add bias
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            result <= sat_add(scaled, bias_d, DATA_WIDTH);
        end if;
    end process;

    -- ==========================================================================
    -- Output
    -- ==========================================================================
    data_out <= std_logic_vector(result);
    valid_out <= valid_d(2);

end rtl;
