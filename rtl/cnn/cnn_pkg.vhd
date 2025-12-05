-- =============================================================================
-- CNN Package - Common types and constants for CNN inference engine
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package cnn_pkg is

    -- ==========================================================================
    -- Data Types and Widths
    -- ==========================================================================
    
    -- Fixed-point representation: Q8.8 (8 integer bits, 8 fractional bits)
    constant DATA_WIDTH         : integer := 16;
    constant FRAC_BITS          : integer := 8;
    constant INT_BITS           : integer := 8;
    
    -- Weight precision (can be reduced for compression)
    constant WEIGHT_WIDTH       : integer := 16;
    constant WEIGHT_FRAC_BITS   : integer := 8;
    
    -- Accumulator width (needs extra bits for MAC operations)
    constant ACC_WIDTH          : integer := 32;
    
    -- Bias width
    constant BIAS_WIDTH         : integer := 16;
    
    -- ==========================================================================
    -- Image/Feature Map Dimensions
    -- ==========================================================================
    
    -- Maximum supported dimensions
    constant MAX_IMG_WIDTH      : integer := 224;
    constant MAX_IMG_HEIGHT     : integer := 224;
    constant MAX_CHANNELS       : integer := 256;
    constant MAX_FILTERS        : integer := 256;
    
    -- Typical input dimensions (MobileNet-style)
    constant INPUT_WIDTH        : integer := 128;
    constant INPUT_HEIGHT       : integer := 128;
    constant INPUT_CHANNELS     : integer := 3;
    
    -- ==========================================================================
    -- Convolution Parameters
    -- ==========================================================================
    
    -- Kernel sizes supported
    constant KERNEL_SIZE_1x1    : integer := 1;
    constant KERNEL_SIZE_3x3    : integer := 3;
    constant KERNEL_SIZE_5x5    : integer := 5;
    constant KERNEL_SIZE_7x7    : integer := 7;
    
    -- Default kernel size
    constant DEFAULT_KERNEL     : integer := 3;
    
    -- Padding modes
    constant PAD_VALID          : std_logic_vector(1 downto 0) := "00";
    constant PAD_SAME           : std_logic_vector(1 downto 0) := "01";
    
    -- Stride options
    constant STRIDE_1           : integer := 1;
    constant STRIDE_2           : integer := 2;
    
    -- ==========================================================================
    -- Pooling Parameters
    -- ==========================================================================
    
    constant POOL_SIZE_2x2      : integer := 2;
    constant POOL_SIZE_3x3      : integer := 3;
    
    -- Pooling types
    constant POOL_MAX           : std_logic := '0';
    constant POOL_AVG           : std_logic := '1';
    
    -- ==========================================================================
    -- Activation Functions
    -- ==========================================================================
    
    constant ACT_NONE           : std_logic_vector(2 downto 0) := "000";
    constant ACT_RELU           : std_logic_vector(2 downto 0) := "001";
    constant ACT_RELU6          : std_logic_vector(2 downto 0) := "010";
    constant ACT_LEAKY_RELU     : std_logic_vector(2 downto 0) := "011";
    constant ACT_SIGMOID        : std_logic_vector(2 downto 0) := "100";
    constant ACT_TANH           : std_logic_vector(2 downto 0) := "101";
    constant ACT_SWISH          : std_logic_vector(2 downto 0) := "110";
    
    -- ReLU6 threshold (6.0 in Q8.8)
    constant RELU6_THRESHOLD    : signed(DATA_WIDTH-1 downto 0) := to_signed(6 * 256, DATA_WIDTH);
    
    -- Leaky ReLU alpha (0.01 approximated as 1/128)
    constant LEAKY_ALPHA_SHIFT  : integer := 7;
    
    -- ==========================================================================
    -- AXI-Stream Interface
    -- ==========================================================================
    
    constant AXIS_DATA_WIDTH    : integer := 64;  -- 4 pixels at 16-bit each
    constant AXIS_TUSER_WIDTH   : integer := 1;   -- Start of frame
    constant AXIS_TID_WIDTH     : integer := 4;   -- Channel ID
    
    -- ==========================================================================
    -- Memory Interface
    -- ==========================================================================
    
    constant MEM_ADDR_WIDTH     : integer := 32;
    constant MEM_DATA_WIDTH     : integer := 128;
    constant BURST_LEN_WIDTH    : integer := 8;
    
    -- ==========================================================================
    -- Buffer Sizes
    -- ==========================================================================
    
    -- Line buffer depth (for 3x3 conv on max width)
    constant LINE_BUF_DEPTH     : integer := MAX_IMG_WIDTH;
    
    -- Weight buffer size per filter
    constant WEIGHT_BUF_SIZE    : integer := DEFAULT_KERNEL * DEFAULT_KERNEL * MAX_CHANNELS;
    
    -- ==========================================================================
    -- Custom Types
    -- ==========================================================================
    
    -- Pixel data type
    subtype pixel_t is signed(DATA_WIDTH-1 downto 0);
    
    -- Weight data type
    subtype weight_t is signed(WEIGHT_WIDTH-1 downto 0);
    
    -- Accumulator type
    subtype acc_t is signed(ACC_WIDTH-1 downto 0);
    
    -- Bias type
    subtype bias_t is signed(BIAS_WIDTH-1 downto 0);
    
    -- 3x3 kernel array types
    type kernel_3x3_t is array (0 to 8) of weight_t;
    type kernel_row_t is array (0 to 2) of weight_t;
    type kernel_matrix_t is array (0 to 2) of kernel_row_t;
    
    -- Line buffer array
    type line_buffer_t is array (0 to LINE_BUF_DEPTH-1) of pixel_t;
    
    -- Pixel window for convolution
    type window_3x3_t is array (0 to 2, 0 to 2) of pixel_t;
    type window_5x5_t is array (0 to 4, 0 to 4) of pixel_t;
    
    -- Feature map slice
    type feature_slice_t is array (natural range <>) of pixel_t;
    
    -- ==========================================================================
    -- Layer Configuration Record
    -- ==========================================================================
    
    type layer_config_t is record
        layer_type      : std_logic_vector(3 downto 0);  -- Conv, Pool, FC, etc.
        input_width     : unsigned(11 downto 0);
        input_height    : unsigned(11 downto 0);
        input_channels  : unsigned(9 downto 0);
        output_channels : unsigned(9 downto 0);
        kernel_size     : unsigned(2 downto 0);
        stride          : unsigned(1 downto 0);
        padding         : std_logic_vector(1 downto 0);
        activation      : std_logic_vector(2 downto 0);
        pool_type       : std_logic;
        pool_size       : unsigned(1 downto 0);
    end record layer_config_t;
    
    -- Layer type constants
    constant LAYER_CONV2D       : std_logic_vector(3 downto 0) := "0001";
    constant LAYER_DWCONV       : std_logic_vector(3 downto 0) := "0010";  -- Depthwise
    constant LAYER_POOL         : std_logic_vector(3 downto 0) := "0011";
    constant LAYER_FC           : std_logic_vector(3 downto 0) := "0100";
    constant LAYER_BATCHNORM    : std_logic_vector(3 downto 0) := "0101";
    constant LAYER_ADD          : std_logic_vector(3 downto 0) := "0110";  -- Skip connection
    constant LAYER_CONCAT       : std_logic_vector(3 downto 0) := "0111";
    
    -- ==========================================================================
    -- Functions
    -- ==========================================================================
    
    -- Saturating addition
    function sat_add(a, b : signed; width : integer) return signed;
    
    -- Fixed-point multiplication with saturation
    function fp_mult(a : pixel_t; b : weight_t) return acc_t;
    
    -- Truncate accumulator to pixel width
    function trunc_acc(acc : acc_t) return pixel_t;
    
    -- ReLU function
    function relu(x : pixel_t) return pixel_t;
    
    -- ReLU6 function
    function relu6(x : pixel_t) return pixel_t;
    
    -- Leaky ReLU function
    function leaky_relu(x : pixel_t) return pixel_t;
    
    -- Max of two values
    function max2(a, b : pixel_t) return pixel_t;
    
    -- Calculate output dimension
    function calc_out_dim(in_dim, kernel, stride, pad : integer) return integer;
    
end package cnn_pkg;

package body cnn_pkg is

    -- Saturating addition
    function sat_add(a, b : signed; width : integer) return signed is
        variable sum : signed(width downto 0);
        variable result : signed(width-1 downto 0);
        constant MAX_VAL : signed(width-1 downto 0) := (width-1 => '0', others => '1');
        constant MIN_VAL : signed(width-1 downto 0) := (width-1 => '1', others => '0');
    begin
        sum := resize(a, width+1) + resize(b, width+1);
        if sum > resize(MAX_VAL, width+1) then
            result := MAX_VAL;
        elsif sum < resize(MIN_VAL, width+1) then
            result := MIN_VAL;
        else
            result := sum(width-1 downto 0);
        end if;
        return result;
    end function;
    
    -- Fixed-point multiplication
    function fp_mult(a : pixel_t; b : weight_t) return acc_t is
        variable product : signed(DATA_WIDTH + WEIGHT_WIDTH - 1 downto 0);
    begin
        product := a * b;
        return resize(product, ACC_WIDTH);
    end function;
    
    -- Truncate accumulator to pixel width with saturation
    function trunc_acc(acc : acc_t) return pixel_t is
        variable shifted : signed(ACC_WIDTH-1 downto 0);
        variable result : pixel_t;
        constant MAX_PIX : pixel_t := (DATA_WIDTH-1 => '0', others => '1');
        constant MIN_PIX : pixel_t := (DATA_WIDTH-1 => '1', others => '0');
    begin
        -- Shift right by fractional bits to get proper scaling
        shifted := shift_right(acc, FRAC_BITS);
        
        -- Saturate to pixel range
        if shifted > resize(MAX_PIX, ACC_WIDTH) then
            result := MAX_PIX;
        elsif shifted < resize(MIN_PIX, ACC_WIDTH) then
            result := MIN_PIX;
        else
            result := shifted(DATA_WIDTH-1 downto 0);
        end if;
        return result;
    end function;
    
    -- ReLU: max(0, x)
    function relu(x : pixel_t) return pixel_t is
    begin
        if x(DATA_WIDTH-1) = '1' then  -- Negative
            return (others => '0');
        else
            return x;
        end if;
    end function;
    
    -- ReLU6: min(max(0, x), 6)
    function relu6(x : pixel_t) return pixel_t is
        variable result : pixel_t;
    begin
        if x(DATA_WIDTH-1) = '1' then  -- Negative
            result := (others => '0');
        elsif x > RELU6_THRESHOLD then
            result := RELU6_THRESHOLD;
        else
            result := x;
        end if;
        return result;
    end function;
    
    -- Leaky ReLU: x if x > 0, else alpha * x
    function leaky_relu(x : pixel_t) return pixel_t is
    begin
        if x(DATA_WIDTH-1) = '1' then  -- Negative
            return shift_right(x, LEAKY_ALPHA_SHIFT);
        else
            return x;
        end if;
    end function;
    
    -- Maximum of two pixels
    function max2(a, b : pixel_t) return pixel_t is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;
    
    -- Calculate output dimension for convolution/pooling
    function calc_out_dim(in_dim, kernel, stride, pad : integer) return integer is
    begin
        return (in_dim + 2*pad - kernel) / stride + 1;
    end function;

end package body cnn_pkg;
