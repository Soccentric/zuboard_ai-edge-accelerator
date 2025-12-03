# ==================================================================================
# Vivado TCL Script for ZUBoard 1CG - GPIO PWM Generation
# Target Device: Zynq UltraScale+ ZU1CG (xczu1cg-sbva484-1-e)
# Description: Creates a Vivado project with PS MIO GPIO configured for PWM output
# ==================================================================================

# Project Configuration
set proj_name "zuboard_pwm_project"
set proj_dir "./zuboard_pwm"
set part_name "xczu1cg-sbva484-1-e"

# Create project directory if it doesn't exist
file mkdir $proj_dir

# Create new project
create_project $proj_name $proj_dir -part $part_name -force

# Set board part if available
catch {set_property board_part zuboard_1cg [current_project]}

# Set project properties
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

# Create block design
create_bd_design "pwm_design"

# Add Zynq UltraScale+ MPSoC IP
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0

# Apply ZUBoard 1CG board preset if available
# Otherwise configure manually
# apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" } [get_bd_cells zynq_ultra_ps_e_0]

# Configure Zynq UltraScale+ PS
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure MIO for GPIO
# Enable GPIO MIO pins for PWM output
set_property -dict [list \
    CONFIG.PSU__GPIO_EMIO__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__GPIO0_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GPIO1_MIO__PERIPHERAL__ENABLE {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Note: Specific MIO pin directions are configured at runtime in software
# The GPIO MIO peripheral handles pin direction control

# Configure UART for debugging
set_property -dict [list \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure USB for JTAG/Debug
set_property -dict [list \
    CONFIG.PSU__USB0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__USB0__PERIPHERAL__IO {MIO 52 .. 63} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure DDR (4GB DDR4)
set_property -dict [list \
    CONFIG.PSU__DDRC__DEVICE_CAPACITY {16384 MBits} \
    CONFIG.PSU__DDRC__ROW_ADDR_COUNT {17} \
    CONFIG.PSU__DDRC__SPEED_BIN {DDR4_1600J} \
    CONFIG.PSU__DDRC__BUS_WIDTH {32 Bit} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Configure Clock
set_property -dict [list \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

# Regenerate layout
regenerate_bd_layout

# Validate block design
validate_bd_design

# Save block design
save_bd_design

# Generate output products
generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/bd/pwm_design/pwm_design.bd]

# Create HDL wrapper
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/pwm_design/pwm_design.bd] -top

add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/pwm_design/hdl/pwm_design_wrapper.vhd

# Set HDL wrapper as top
set_property top pwm_design_wrapper [current_fileset]

# Create constraint file for pin assignments
set constraint_file "$proj_dir/$proj_name.srcs/constrs_1/new/zuboard_pins.xdc"
file mkdir [file dirname $constraint_file]

set constr_fh [open $constraint_file w]
puts $constr_fh "# =================================================================================="
puts $constr_fh "# ZUBoard 1CG Pin Constraints"
puts $constr_fh "# =================================================================================="
puts $constr_fh ""
puts $constr_fh "# MIO GPIO pins are internally connected - no external pin constraints needed"
puts $constr_fh "# PS MIO pins are configured through PS configuration"
puts $constr_fh ""
puts $constr_fh "# No PL clocks in this design - clock constraints not needed"
puts $constr_fh ""
close $constr_fh

add_files -fileset constrs_1 -norecurse $constraint_file

# Create sample C code for PWM generation
set sw_dir "$proj_dir/software"
file mkdir $sw_dir

set c_file "$sw_dir/pwm_gpio.c"
set c_fh [open $c_file w]
puts $c_fh "/*"
puts $c_fh " * PWM Generation using PS MIO GPIO"
puts $c_fh " * ZUBoard 1CG - Zynq UltraScale+ MPSoC"
puts $c_fh " */"
puts $c_fh ""
puts $c_fh "#include <stdio.h>"
puts $c_fh "#include \"xparameters.h\""
puts $c_fh "#include \"xgpiops.h\""
puts $c_fh "#include \"sleep.h\""
puts $c_fh ""
puts $c_fh "#define GPIO_DEVICE_ID XPAR_XGPIOPS_0_DEVICE_ID"
puts $c_fh "#define MIO_PWM_PIN 26  // MIO pin for PWM output"
puts $c_fh ""
puts $c_fh "XGpioPs Gpio;"
puts $c_fh ""
puts $c_fh "void pwm_generate(u32 pin, u32 duty_cycle_us, u32 period_us, u32 duration_ms) {"
puts $c_fh "    u32 cycles = (duration_ms * 1000) / period_us;"
puts $c_fh "    u32 i;"
puts $c_fh "    "
puts $c_fh "    for (i = 0; i < cycles; i++) {"
puts $c_fh "        XGpioPs_WritePin(&Gpio, pin, 1);"
puts $c_fh "        usleep(duty_cycle_us);"
puts $c_fh "        XGpioPs_WritePin(&Gpio, pin, 0);"
puts $c_fh "        usleep(period_us - duty_cycle_us);"
puts $c_fh "    }"
puts $c_fh "}"
puts $c_fh ""
puts $c_fh "int main() {"
puts $c_fh "    XGpioPs_Config *ConfigPtr;"
puts $c_fh "    int Status;"
puts $c_fh "    "
puts $c_fh "    printf(\"PWM GPIO Test - ZUBoard 1CG\\r\\n\");"
puts $c_fh "    "
puts $c_fh "    // Initialize GPIO"
puts $c_fh "    ConfigPtr = XGpioPs_LookupConfig(GPIO_DEVICE_ID);"
puts $c_fh "    if (ConfigPtr == NULL) {"
puts $c_fh "        printf(\"GPIO Lookup Failed\\r\\n\");"
puts $c_fh "        return XST_FAILURE;"
puts $c_fh "    }"
puts $c_fh "    "
puts $c_fh "    Status = XGpioPs_CfgInitialize(&Gpio, ConfigPtr, ConfigPtr->BaseAddr);"
puts $c_fh "    if (Status != XST_SUCCESS) {"
puts $c_fh "        printf(\"GPIO Init Failed\\r\\n\");"
puts $c_fh "        return XST_FAILURE;"
puts $c_fh "    }"
puts $c_fh "    "
puts $c_fh "    // Set MIO pin as output"
puts $c_fh "    XGpioPs_SetDirectionPin(&Gpio, MIO_PWM_PIN, 1);"
puts $c_fh "    XGpioPs_SetOutputEnablePin(&Gpio, MIO_PWM_PIN, 1);"
puts $c_fh "    "
puts $c_fh "    printf(\"Generating PWM on MIO Pin %d\\r\\n\", MIO_PWM_PIN);"
puts $c_fh "    "
puts $c_fh "    // Generate PWM with different duty cycles"
puts $c_fh "    while(1) {"
puts $c_fh "        printf(\"25%% Duty Cycle\\r\\n\");"
puts $c_fh "        pwm_generate(MIO_PWM_PIN, 250, 1000, 2000);  // 25% duty, 1kHz, 2s"
puts $c_fh "        "
puts $c_fh "        printf(\"50%% Duty Cycle\\r\\n\");"
puts $c_fh "        pwm_generate(MIO_PWM_PIN, 500, 1000, 2000);  // 50% duty, 1kHz, 2s"
puts $c_fh "        "
puts $c_fh "        printf(\"75%% Duty Cycle\\r\\n\");"
puts $c_fh "        pwm_generate(MIO_PWM_PIN, 750, 1000, 2000);  // 75% duty, 1kHz, 2s"
puts $c_fh "    }"
puts $c_fh "    "
puts $c_fh "    return 0;"
puts $c_fh "}"
close $c_fh

puts "INFO: C source code created at: $c_file"

# Launch synthesis (optional - comment out if you just want to create the project)
# launch_runs synth_1
# wait_on_run synth_1

# Launch implementation (optional)
# launch_runs impl_1
# wait_on_run impl_1

# Generate bitstream (optional)
# launch_runs impl_1 -to_step write_bitstream
# wait_on_run impl_1

puts "=========================================================================="
puts "Project Creation Complete!"
puts "=========================================================================="
puts "Project Name: $proj_name"
puts "Project Directory: $proj_dir"
puts "Target Device: $part_name"
puts ""
puts "Next Steps:"
puts "1. Open Vivado and load the project: $proj_dir/$proj_name.xpr"
puts "2. Review the block design: pwm_design"
puts "3. Generate bitstream: Tools -> Generate Bitstream"
puts "4. Export hardware (include bitstream): File -> Export -> Export Hardware"
puts "5. Create Vitis workspace and import the C code from: $sw_dir/pwm_gpio.c"
puts "6. Build and run the application on the ZUBoard 1CG"
puts "=========================================================================="