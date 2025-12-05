-- =============================================================================
-- Activation Function Unit with Pipelined Processing
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Supports:
--   - ReLU: max(0, x)
--   - ReLU6: min(max(0, x), 6)
--   - Leaky ReLU: x if x > 0, else alpha * x
--   - Sigmoid: 1 / (1 + exp(-x)) - LUT based
--   - Tanh: (exp(x) - exp(-x)) / (exp(x) + exp(-x)) - LUT based
--   - Swish: x * sigmoid(x)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity activation_unit is
    generic (
        USE_LUT_SIGMOID : boolean := true;
        USE_LUT_TANH    : boolean := true;
        LUT_DEPTH       : integer := 256
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_activation  : in  std_logic_vector(2 downto 0);
        
        -- Input
        data_in         : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_in        : in  std_logic;
        
        -- Output
        data_out        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        valid_out       : out std_logic
    );
end activation_unit;

architecture rtl of activation_unit is

    -- LUT for sigmoid (precomputed values)
    type sigmoid_lut_t is array (0 to LUT_DEPTH-1) of pixel_t;
    
    -- Sigmoid LUT initialization function
    -- Values are in Q8.8 format, input range [-8, 8] mapped to [0, 255]
    function init_sigmoid_lut return sigmoid_lut_t is
        variable lut : sigmoid_lut_t;
        variable x : real;
        variable y : real;
        variable idx : integer;
    begin
        for i in 0 to LUT_DEPTH-1 loop
            -- Map index to input range [-8, 8]
            x := (real(i) / real(LUT_DEPTH-1)) * 16.0 - 8.0;
            -- Sigmoid: 1 / (1 + exp(-x))
            y := 1.0 / (1.0 + exp(-x));
            -- Convert to Q8.8 (multiply by 256)
            idx := integer(y * 256.0);
            if idx > 32767 then idx := 32767; end if;
            if idx < -32768 then idx := -32768; end if;
            lut(i) := to_signed(idx, DATA_WIDTH);
        end loop;
        return lut;
    end function;
    
    -- Tanh LUT initialization
    function init_tanh_lut return sigmoid_lut_t is
        variable lut : sigmoid_lut_t;
        variable x : real;
        variable y : real;
        variable idx : integer;
    begin
        for i in 0 to LUT_DEPTH-1 loop
            -- Map index to input range [-4, 4]
            x := (real(i) / real(LUT_DEPTH-1)) * 8.0 - 4.0;
            -- Tanh
            if x > 20.0 then
                y := 1.0;
            elsif x < -20.0 then
                y := -1.0;
            else
                y := (exp(x) - exp(-x)) / (exp(x) + exp(-x));
            end if;
            -- Convert to Q8.8
            idx := integer(y * 256.0);
            if idx > 32767 then idx := 32767; end if;
            if idx < -32768 then idx := -32768; end if;
            lut(i) := to_signed(idx, DATA_WIDTH);
        end loop;
        return lut;
    end function;
    
    -- LUT signals
    signal sigmoid_lut  : sigmoid_lut_t := init_sigmoid_lut;
    signal tanh_lut     : sigmoid_lut_t := init_tanh_lut;
    
    -- Input as signed
    signal input_pixel  : pixel_t;
    
    -- Intermediate results
    signal relu_out     : pixel_t;
    signal relu6_out    : pixel_t;
    signal leaky_out    : pixel_t;
    signal sigmoid_out  : pixel_t;
    signal tanh_out     : pixel_t;
    signal swish_out    : pixel_t;
    
    -- LUT address calculation
    signal lut_addr_sig : unsigned(7 downto 0);
    signal lut_addr_tanh: unsigned(7 downto 0);
    
    -- Pipeline
    signal result_mux   : pixel_t;
    signal valid_pipe   : std_logic_vector(2 downto 0);
    signal act_sel_d    : std_logic_vector(2 downto 0);

begin

    input_pixel <= signed(data_in);

    -- ==========================================================================
    -- ReLU: max(0, x)
    -- ==========================================================================
    relu_out <= (others => '0') when input_pixel(DATA_WIDTH-1) = '1' else input_pixel;

    -- ==========================================================================
    -- ReLU6: min(max(0, x), 6)
    -- ==========================================================================
    process(input_pixel)
    begin
        if input_pixel(DATA_WIDTH-1) = '1' then
            relu6_out <= (others => '0');
        elsif input_pixel > RELU6_THRESHOLD then
            relu6_out <= RELU6_THRESHOLD;
        else
            relu6_out <= input_pixel;
        end if;
    end process;

    -- ==========================================================================
    -- Leaky ReLU: x if x > 0, else 0.01 * x (approximated as x >> 7)
    -- ==========================================================================
    leaky_out <= input_pixel when input_pixel(DATA_WIDTH-1) = '0' 
                 else shift_right(input_pixel, LEAKY_ALPHA_SHIFT);

    -- ==========================================================================
    -- Sigmoid LUT Address Calculation
    -- Map input from [-8, 8] (Q8.8: [-2048, 2048]) to [0, 255]
    -- ==========================================================================
    process(input_pixel)
        variable scaled : signed(DATA_WIDTH-1 downto 0);
        variable addr : unsigned(7 downto 0);
    begin
        -- Clamp to [-8, 8] range first
        if input_pixel < to_signed(-2048, DATA_WIDTH) then
            scaled := to_signed(-2048, DATA_WIDTH);
        elsif input_pixel > to_signed(2047, DATA_WIDTH) then
            scaled := to_signed(2047, DATA_WIDTH);
        else
            scaled := input_pixel;
        end if;
        
        -- Map to [0, 255]: (x + 2048) * 255 / 4096 ≈ (x + 2048) >> 4
        addr := unsigned(scaled(11 downto 4)) + 128;
        lut_addr_sig <= addr;
    end process;

    -- ==========================================================================
    -- Tanh LUT Address Calculation  
    -- Map input from [-4, 4] (Q8.8: [-1024, 1024]) to [0, 255]
    -- ==========================================================================
    process(input_pixel)
        variable scaled : signed(DATA_WIDTH-1 downto 0);
        variable addr : unsigned(7 downto 0);
    begin
        if input_pixel < to_signed(-1024, DATA_WIDTH) then
            scaled := to_signed(-1024, DATA_WIDTH);
        elsif input_pixel > to_signed(1023, DATA_WIDTH) then
            scaled := to_signed(1023, DATA_WIDTH);
        else
            scaled := input_pixel;
        end if;
        
        addr := unsigned(scaled(10 downto 3)) + 128;
        lut_addr_tanh <= addr;
    end process;

    -- ==========================================================================
    -- LUT Read (registered for timing)
    -- ==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            sigmoid_out <= sigmoid_lut(to_integer(lut_addr_sig));
            tanh_out <= tanh_lut(to_integer(lut_addr_tanh));
        end if;
    end process;

    -- ==========================================================================
    -- Swish: x * sigmoid(x)
    -- Computed as: input_pixel * sigmoid_out (needs extra pipeline stage)
    -- ==========================================================================
    process(clk)
        variable product : signed(2*DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            product := input_pixel * sigmoid_out;
            -- Scale back: sigmoid output is in [0, 1] as Q8.8, so >> 8
            swish_out <= product(DATA_WIDTH+FRAC_BITS-1 downto FRAC_BITS);
        end if;
    end process;

    -- ==========================================================================
    -- Pipeline and Output Mux
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid_pipe <= (others => '0');
            act_sel_d <= (others => '0');
        elsif rising_edge(clk) then
            valid_pipe(0) <= valid_in;
            valid_pipe(2 downto 1) <= valid_pipe(1 downto 0);
            
            act_sel_d <= cfg_activation;
        end if;
    end process;
    
    -- Output multiplexer (select based on activation type)
    process(clk)
    begin
        if rising_edge(clk) then
            case act_sel_d is
                when ACT_RELU =>
                    result_mux <= relu_out;
                when ACT_RELU6 =>
                    result_mux <= relu6_out;
                when ACT_LEAKY_RELU =>
                    result_mux <= leaky_out;
                when ACT_SIGMOID =>
                    result_mux <= sigmoid_out;
                when ACT_TANH =>
                    result_mux <= tanh_out;
                when ACT_SWISH =>
                    result_mux <= swish_out;
                when others =>
                    result_mux <= input_pixel;  -- Pass through
            end case;
        end if;
    end process;

    -- ==========================================================================
    -- Output
    -- ==========================================================================
    data_out <= std_logic_vector(result_mux);
    valid_out <= valid_pipe(1);  -- Adjusted for pipeline depth

end rtl;
