-- =============================================================================
-- AXI-Stream Video Input Interface
-- Target: ZUBoard 1CG (xczu1cg-sbva484-1-e)
-- 
-- Features:
--   - Receives video frames from camera/DMA via AXI-Stream
--   - RGB to fixed-point conversion
--   - Frame synchronization with SOF/EOL signals
--   - Configurable input resolution
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.cnn_pkg.all;

entity axis_video_input is
    generic (
        INPUT_WIDTH     : integer := 128;
        INPUT_HEIGHT    : integer := 128;
        PIXEL_WIDTH     : integer := 24;    -- RGB888
        OUTPUT_WIDTH    : integer := DATA_WIDTH
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Configuration
        cfg_enable      : in  std_logic;
        cfg_normalize   : in  std_logic;    -- Normalize to [-1, 1] or [0, 1]
        
        -- AXI-Stream Video Input (RGB)
        s_axis_tdata    : in  std_logic_vector(PIXEL_WIDTH-1 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;    -- End of line
        s_axis_tuser    : in  std_logic;    -- Start of frame
        
        -- AXI-Stream Output (Fixed-point, per channel)
        m_axis_r_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        m_axis_g_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        m_axis_b_tdata  : out std_logic_vector(OUTPUT_WIDTH-1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic;
        
        -- Status
        frame_count     : out std_logic_vector(31 downto 0);
        pixel_count     : out std_logic_vector(31 downto 0)
    );
end axis_video_input;

architecture rtl of axis_video_input is

    -- RGB extraction
    signal r_in, g_in, b_in : unsigned(7 downto 0);
    
    -- Normalized values (Q8.8 format)
    signal r_norm, g_norm, b_norm : pixel_t;
    
    -- Pipeline registers
    signal valid_d      : std_logic_vector(1 downto 0);
    signal last_d       : std_logic_vector(1 downto 0);
    signal user_d       : std_logic_vector(1 downto 0);
    
    -- Counters
    signal frame_cnt    : unsigned(31 downto 0);
    signal pixel_cnt    : unsigned(31 downto 0);
    
    -- Internal control
    signal input_accept : std_logic;

begin

    -- ==========================================================================
    -- RGB Extraction (assuming RGB888 format: R[23:16], G[15:8], B[7:0])
    -- ==========================================================================
    r_in <= unsigned(s_axis_tdata(23 downto 16));
    g_in <= unsigned(s_axis_tdata(15 downto 8));
    b_in <= unsigned(s_axis_tdata(7 downto 0));

    -- ==========================================================================
    -- Normalization Pipeline
    -- Convert 8-bit [0, 255] to Q8.8 format
    -- If cfg_normalize = '0': [0, 255] -> [0, 1] in Q8.8 (value stays same, just interpreted)
    -- If cfg_normalize = '1': [0, 255] -> [-1, 1] in Q8.8 (subtract 128, then scale)
    -- ==========================================================================
    process(clk, rst_n)
        variable r_ext, g_ext, b_ext : signed(DATA_WIDTH-1 downto 0);
    begin
        if rst_n = '0' then
            r_norm <= (others => '0');
            g_norm <= (others => '0');
            b_norm <= (others => '0');
        elsif rising_edge(clk) then
            if s_axis_tvalid = '1' and input_accept = '1' then
                if cfg_normalize = '1' then
                    -- Map [0, 255] to [-1, 1] in Q8.8
                    -- Formula: (pixel - 128) * 2 = (pixel - 128) << 1
                    -- In Q8.8: -1 = -256, 1 = 256
                    r_ext := resize(signed('0' & r_in), DATA_WIDTH) - 128;
                    g_ext := resize(signed('0' & g_in), DATA_WIDTH) - 128;
                    b_ext := resize(signed('0' & b_in), DATA_WIDTH) - 128;
                    r_norm <= shift_left(r_ext, 1);
                    g_norm <= shift_left(g_ext, 1);
                    b_norm <= shift_left(b_ext, 1);
                else
                    -- Map [0, 255] to [0, 1] in Q8.8
                    -- In Q8.8: 1.0 = 256, so pixel value maps to pixel
                    r_norm <= resize(signed('0' & r_in), DATA_WIDTH);
                    g_norm <= resize(signed('0' & g_in), DATA_WIDTH);
                    b_norm <= resize(signed('0' & b_in), DATA_WIDTH);
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Pipeline Control
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid_d <= (others => '0');
            last_d <= (others => '0');
            user_d <= (others => '0');
        elsif rising_edge(clk) then
            valid_d(0) <= s_axis_tvalid and input_accept and cfg_enable;
            valid_d(1) <= valid_d(0);
            
            last_d(0) <= s_axis_tlast;
            last_d(1) <= last_d(0);
            
            user_d(0) <= s_axis_tuser;
            user_d(1) <= user_d(0);
        end if;
    end process;

    -- ==========================================================================
    -- Frame and Pixel Counters
    -- ==========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            frame_cnt <= (others => '0');
            pixel_cnt <= (others => '0');
        elsif rising_edge(clk) then
            if s_axis_tvalid = '1' and input_accept = '1' then
                if s_axis_tuser = '1' then
                    -- Start of new frame
                    frame_cnt <= frame_cnt + 1;
                    pixel_cnt <= (others => '0');
                else
                    pixel_cnt <= pixel_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Output Assignment
    -- ==========================================================================
    input_accept <= cfg_enable and (m_axis_tready or not valid_d(1));
    s_axis_tready <= input_accept;
    
    m_axis_r_tdata <= std_logic_vector(r_norm);
    m_axis_g_tdata <= std_logic_vector(g_norm);
    m_axis_b_tdata <= std_logic_vector(b_norm);
    m_axis_tvalid <= valid_d(1);
    m_axis_tlast <= last_d(1);
    m_axis_tuser <= user_d(1);
    
    frame_count <= std_logic_vector(frame_cnt);
    pixel_count <= std_logic_vector(pixel_cnt);

end rtl;
