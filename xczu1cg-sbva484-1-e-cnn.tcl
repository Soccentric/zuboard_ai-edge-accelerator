# ==================================================================================
# Vivado TCL Script for ZUBoard 1CG - AI Edge Accelerator CNN Inference Engine
# Target Device: Zynq UltraScale+ ZU1CG (xczu1cg-sbva484-1-e)
#
# Description: Creates a complete CNN inference accelerator system with:
#   - Custom Conv2D and Pooling engines
#   - DMA for camera input and weight loading
#   - AXI-Lite control interface
#   - Real-time object detection/classification support
#
# Usage (command line, no GUI):
#   vivado -mode batch -source xczu1cg-sbva484-1-e-cnn.tcl
# ==================================================================================

# Project Configuration
set proj_name "ai_edge_accelerator"
set proj_dir "./ai_edge_accelerator"
set part_name "xczu1cg-sbva484-1-e"

# RTL source directories
set rtl_cnn_dir "./rtl/cnn"
set rtl_axi_dir "./rtl/axi"
set rtl_video_dir "./rtl/video"

# Create project directory if it doesn't exist
file mkdir $proj_dir

# Create new project
create_project $proj_name $proj_dir -part $part_name -force
set_property BOARD_PART_REPO_PATHS [get_property BOARD_PART_REPO_PATHS [current_project]] [current_project]

# Set board part if available
catch {set_property board_part avnet.com:zuboard_1cg:part0:1.0 [current_project]}

# Set project properties
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

# ==================================================================================
# Add RTL Source Files
# ==================================================================================

# Add CNN RTL files
add_files -norecurse [glob -nocomplain $rtl_cnn_dir/*.vhd]
add_files -norecurse [glob -nocomplain $rtl_axi_dir/*.vhd]
add_files -norecurse [glob -nocomplain $rtl_video_dir/*.vhd]

# Update compile order
update_compile_order -fileset sources_1

# ==================================================================================
# Create Block Design
# ==================================================================================
create_bd_design "cnn_system"

# Add Zynq UltraScale+ MPSoC IP
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0

# Configure Zynq UltraScale+ PS for high-performance data movement
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {1} \
    CONFIG.PSU__USE__S_AXI_GP0 {1} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure GPIO for status LEDs
set_property -dict [list \
    CONFIG.PSU__GPIO_EMIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GPIO_EMIO__PERIPHERAL__IO {4} \
    CONFIG.PSU__GPIO0_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GPIO1_MIO__PERIPHERAL__ENABLE {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure UART for debugging
set_property -dict [list \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure USB
set_property -dict [list \
    CONFIG.PSU__USB0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__USB0__PERIPHERAL__IO {MIO 52 .. 63} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure DDR (4GB DDR4) for large model weights and feature maps
set_property -dict [list \
    CONFIG.PSU__DDRC__DEVICE_CAPACITY {16384 MBits} \
    CONFIG.PSU__DDRC__ROW_ADDR_COUNT {17} \
    CONFIG.PSU__DDRC__SPEED_BIN {DDR4_1600J} \
    CONFIG.PSU__DDRC__BUS_WIDTH {32 Bit} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure Clocks - 100MHz for logic, 200MHz for high-speed processing
set_property -dict [list \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__PL1_REF_CTRL__FREQMHZ {200} \
    CONFIG.PSU__USE__FABRIC__RST {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# ==================================================================================
# Add DMA for Video Input (AXI DMA)
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_video

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
    ] [get_bd_cells axi_dma_video]

# ==================================================================================
# Add DMA for Weight Loading
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_weights

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {256} \
    ] [get_bd_cells axi_dma_weights]

# ==================================================================================
# Add AXI Interconnect for Memory Access
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon

set_property -dict [list \
    CONFIG.NUM_SI {3} \
    CONFIG.NUM_MI {1} \
    ] [get_bd_cells axi_mem_intercon]

# ==================================================================================
# Add AXI Interconnect for Peripheral Access
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_periph_intercon

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {4} \
    ] [get_bd_cells axi_periph_intercon]

# ==================================================================================
# Add Processor System Reset
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

# ==================================================================================
# Add CNN Accelerator as RTL Module
# ==================================================================================
create_bd_cell -type module -reference cnn_accelerator_top cnn_accelerator_0

# ==================================================================================
# Add AXI Stream Data Width Converter (DMA 32-bit to CNN 24-bit for video)
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_video

set_property -dict [list \
    CONFIG.S_TDATA_NUM_BYTES {4} \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    ] [get_bd_cells axis_dwidth_video]

# ==================================================================================
# Add Interrupt Controller
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_0

set_property -dict [list \
    CONFIG.C_IRQ_CONNECTION {1} \
    ] [get_bd_cells axi_intc_0]

# ==================================================================================
# Add Concat for Interrupts
# ==================================================================================
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0

set_property -dict [list \
    CONFIG.NUM_PORTS {4} \
    ] [get_bd_cells xlconcat_0]

# ==================================================================================
# Connect Clocks and Resets
# ==================================================================================

# Connect PL clock
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins cnn_accelerator_0/aclk] \
    [get_bd_pins axi_dma_video/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_video/m_axi_s2mm_aclk] \
    [get_bd_pins axi_dma_video/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_weights/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_weights/s_axi_lite_aclk] \
    [get_bd_pins axi_mem_intercon/ACLK] \
    [get_bd_pins axi_mem_intercon/S00_ACLK] \
    [get_bd_pins axi_mem_intercon/S01_ACLK] \
    [get_bd_pins axi_mem_intercon/S02_ACLK] \
    [get_bd_pins axi_mem_intercon/M00_ACLK] \
    [get_bd_pins axi_periph_intercon/ACLK] \
    [get_bd_pins axi_periph_intercon/S00_ACLK] \
    [get_bd_pins axi_periph_intercon/M00_ACLK] \
    [get_bd_pins axi_periph_intercon/M01_ACLK] \
    [get_bd_pins axi_periph_intercon/M02_ACLK] \
    [get_bd_pins axi_periph_intercon/M03_ACLK] \
    [get_bd_pins axis_dwidth_video/aclk] \
    [get_bd_pins axi_intc_0/s_axi_aclk] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

# Connect synchronized resets
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins cnn_accelerator_0/aresetn] \
    [get_bd_pins axi_dma_video/axi_resetn] \
    [get_bd_pins axi_dma_weights/axi_resetn] \
    [get_bd_pins axi_mem_intercon/ARESETN] \
    [get_bd_pins axi_mem_intercon/S00_ARESETN] \
    [get_bd_pins axi_mem_intercon/S01_ARESETN] \
    [get_bd_pins axi_mem_intercon/S02_ARESETN] \
    [get_bd_pins axi_mem_intercon/M00_ARESETN] \
    [get_bd_pins axi_periph_intercon/ARESETN] \
    [get_bd_pins axi_periph_intercon/S00_ARESETN] \
    [get_bd_pins axi_periph_intercon/M00_ARESETN] \
    [get_bd_pins axi_periph_intercon/M01_ARESETN] \
    [get_bd_pins axi_periph_intercon/M02_ARESETN] \
    [get_bd_pins axi_periph_intercon/M03_ARESETN] \
    [get_bd_pins axis_dwidth_video/aresetn] \
    [get_bd_pins axi_intc_0/s_axi_aresetn]

# ==================================================================================
# Connect AXI Interfaces
# ==================================================================================

# PS Master to Peripheral Interconnect
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins axi_periph_intercon/S00_AXI]

# Peripheral Interconnect to peripherals
connect_bd_intf_net [get_bd_intf_pins axi_periph_intercon/M00_AXI] \
    [get_bd_intf_pins cnn_accelerator_0/s_axi]
connect_bd_intf_net [get_bd_intf_pins axi_periph_intercon/M01_AXI] \
    [get_bd_intf_pins axi_dma_video/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_periph_intercon/M02_AXI] \
    [get_bd_intf_pins axi_dma_weights/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_periph_intercon/M03_AXI] \
    [get_bd_intf_pins axi_intc_0/s_axi]

# DMA to Memory Interconnect
connect_bd_intf_net [get_bd_intf_pins axi_dma_video/M_AXI_MM2S] \
    [get_bd_intf_pins axi_mem_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_video/M_AXI_S2MM] \
    [get_bd_intf_pins axi_mem_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_weights/M_AXI_MM2S] \
    [get_bd_intf_pins axi_mem_intercon/S02_AXI]

# Memory Interconnect to PS HP Slave
connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] \
    [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# ==================================================================================
# Connect AXI-Stream Data Path
# ==================================================================================

# DMA MM2S -> Width Converter -> CNN Video Input
connect_bd_intf_net [get_bd_intf_pins axi_dma_video/M_AXIS_MM2S] \
    [get_bd_intf_pins axis_dwidth_video/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_dwidth_video/M_AXIS] \
    [get_bd_intf_pins cnn_accelerator_0/s_axis_video]

# CNN Result Output -> DMA S2MM (would need width converter in full implementation)
# For now, connect result directly to provide classification output
# connect_bd_intf_net [get_bd_intf_pins cnn_accelerator_0/m_axis_result] \
#     [get_bd_intf_pins axi_dma_video/S_AXIS_S2MM]

# ==================================================================================
# Connect Interrupts
# ==================================================================================
connect_bd_net [get_bd_pins cnn_accelerator_0/irq] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_video/mm2s_introut] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins axi_dma_video/s2mm_introut] [get_bd_pins xlconcat_0/In2]
connect_bd_net [get_bd_pins axi_dma_weights/mm2s_introut] [get_bd_pins xlconcat_0/In3]

connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins axi_intc_0/intr]
connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

# ==================================================================================
# Assign Addresses
# ==================================================================================
assign_bd_address

# Set specific address ranges
set_property offset 0x80000000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_cnn_accelerator_0_reg0}]
set_property range 4K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_cnn_accelerator_0_reg0}]

set_property offset 0x80010000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_dma_video_Reg}]
set_property range 4K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_dma_video_Reg}]

set_property offset 0x80020000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_dma_weights_Reg}]
set_property range 4K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_dma_weights_Reg}]

set_property offset 0x80030000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_intc_0_Reg}]
set_property range 4K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_intc_0_Reg}]

# ==================================================================================
# Regenerate and Validate
# ==================================================================================
regenerate_bd_layout
validate_bd_design
save_bd_design

# ==================================================================================
# Generate Output Products
# ==================================================================================
generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/bd/cnn_system/cnn_system.bd]

# Create HDL wrapper
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/cnn_system/cnn_system.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/cnn_system/hdl/cnn_system_wrapper.vhd

# Set HDL wrapper as top
set_property top cnn_system_wrapper [current_fileset]

# ==================================================================================
# Create Constraint File
# ==================================================================================
set constraint_file "$proj_dir/$proj_name.srcs/constrs_1/new/zuboard_cnn.xdc"
file mkdir [file dirname $constraint_file]

set constr_fh [open $constraint_file w]
puts $constr_fh "# =================================================================================="
puts $constr_fh "# ZUBoard 1CG AI Edge Accelerator Pin Constraints"
puts $constr_fh "# =================================================================================="
puts $constr_fh ""
puts $constr_fh "# Timing Constraints"
puts $constr_fh "# PL Clock is 100MHz from PS"
puts $constr_fh "create_clock -period 10.000 -name pl_clk0 \[get_pins cnn_system_i/zynq_ultra_ps_e_0/inst/PS8_i/PLCLK\[0\]\]"
puts $constr_fh ""
puts $constr_fh "# False paths for asynchronous resets"
puts $constr_fh "set_false_path -from \[get_pins cnn_system_i/proc_sys_reset_0/U0/ACTIVE_LOW_PR_OUT_DFF\[0\].peripheral_aresetn_reg/C\]"
puts $constr_fh ""
puts $constr_fh "# Multicycle paths for CNN datapath (relax timing for complex logic)"
puts $constr_fh "# set_multicycle_path 2 -setup -from \[get_pins cnn_system_i/cnn_accelerator_0/inst/*/mac_acc_reg*/C\]"
puts $constr_fh "# set_multicycle_path 1 -hold -from \[get_pins cnn_system_i/cnn_accelerator_0/inst/*/mac_acc_reg*/C\]"
puts $constr_fh ""
puts $constr_fh "# GPIO EMIO pins for status LEDs (directly on PL)"
puts $constr_fh "# set_property PACKAGE_PIN <pin> \[get_ports {gpio_emio_tri_io\[0\]}\]"
puts $constr_fh "# set_property IOSTANDARD LVCMOS18 \[get_ports {gpio_emio_tri_io\[0\]}\]"
puts $constr_fh ""
close $constr_fh

add_files -fileset constrs_1 -norecurse $constraint_file

# ==================================================================================
# Run Synthesis
# ==================================================================================
puts "=========================================================================="
puts "Starting Synthesis..."
puts "=========================================================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

puts "INFO: Synthesis completed successfully"

# ==================================================================================
# Run Implementation
# ==================================================================================
puts "=========================================================================="
puts "Starting Implementation..."
puts "=========================================================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

puts "INFO: Implementation completed successfully"

# ==================================================================================
# Generate Bitstream
# ==================================================================================
puts "=========================================================================="
puts "Generating Bitstream..."
puts "=========================================================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# ==================================================================================
# Export Hardware (XSA)
# ==================================================================================
set xsa_file "[pwd]/$proj_dir/${proj_name}.xsa"
write_hw_platform -fixed -include_bit -force -file $xsa_file

puts "INFO: XSA file generated at: $xsa_file"

# ==================================================================================
# Generate Vitis Platform Script
# ==================================================================================
set vitis_script "[pwd]/$proj_dir/create_vitis_project.tcl"
set vitis_ws "[pwd]/$proj_dir/vitis_workspace"
set platform_name "ai_edge_platform"
set app_name "cnn_inference_app"

set vitis_fh [open $vitis_script w]
puts $vitis_fh "# Vitis XSCT Script for AI Edge Accelerator"
puts $vitis_fh "# Run with: xsct create_vitis_project.tcl"
puts $vitis_fh ""
puts $vitis_fh "set xsa_file \"$xsa_file\""
puts $vitis_fh "set vitis_ws \"$vitis_ws\""
puts $vitis_fh "set platform_name \"$platform_name\""
puts $vitis_fh "set app_name \"$app_name\""
puts $vitis_fh ""
puts $vitis_fh "file mkdir \$vitis_ws"
puts $vitis_fh "setws \$vitis_ws"
puts $vitis_fh ""
puts $vitis_fh "# Create platform"
puts $vitis_fh "platform create -name \$platform_name -hw \$xsa_file -proc psu_cortexa53_0 -os standalone"
puts $vitis_fh "platform generate"
puts $vitis_fh ""
puts $vitis_fh "# Create application"
puts $vitis_fh "app create -name \$app_name -platform \$platform_name -template \"Empty Application(C)\""
puts $vitis_fh ""
puts $vitis_fh "# Build application"
puts $vitis_fh "app build -name \$app_name"
puts $vitis_fh ""
puts $vitis_fh "puts \"Vitis project created successfully!\""
puts $vitis_fh "exit"
close $vitis_fh

# Close project
close_project

puts "=========================================================================="
puts "AI Edge Accelerator Build Complete!"
puts "=========================================================================="
puts "Project: $proj_name"
puts "Directory: $proj_dir"
puts "XSA File: $xsa_file"
puts ""
puts "To create Vitis application:"
puts "  cd $proj_dir && xsct create_vitis_project.tcl"
puts "=========================================================================="

exit
