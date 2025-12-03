# ==================================================================================
# Vivado TCL Script for ZUBoard 1CG - GPIO PWM Generation
# Target Device: Zynq UltraScale+ ZU1CG (xczu1cg-sbva484-1-e)
# Description: Creates a Vivado project with PS MIO GPIO configured for PWM output
#
# Usage (command line, no GUI):
#   vivado -mode batch -source xczu1cg-sbva484-1-e-pwm.tcl
# ==================================================================================

# Project Configuration
set proj_name "zuboard_pwm_project"
set proj_dir "./zuboard_pwm"
set part_name "xczu1cg-sbva484-1-e"

# Create project directory if it doesn't exist
file mkdir $proj_dir

# Create new project (in-memory for batch mode)
create_project $proj_name $proj_dir -part $part_name -force
set_property BOARD_PART_REPO_PATHS [get_property BOARD_PART_REPO_PATHS [current_project]] [current_project]

# Set board part if available
catch {set_property board_part avnet.com:zuboard_1cg:part0:1.0 [current_project]}

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

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

# Launch implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Export hardware with bitstream (XSA file)
set xsa_file "[pwd]/$proj_dir/${proj_name}.xsa"
write_hw_platform -fixed -include_bit -force -file $xsa_file

puts "INFO: XSA file generated at: $xsa_file"

# Save and close Vivado project
save_project_as $proj_name $proj_dir -force
close_project

puts "=========================================================================="
puts "Vivado Build Complete!"
puts "=========================================================================="
puts "XSA File: $xsa_file"
puts ""
puts "Now creating Vitis project..."
puts "=========================================================================="

# ==================================================================================
# Vitis Platform and Application Creation (using XSCT)
# Note: This section uses XSCT commands which are compatible with Vitis command line
# ==================================================================================

# Get absolute paths
set script_dir [pwd]
set xsa_abs_path "[pwd]/$proj_dir/${proj_name}.xsa"
set vitis_ws "[pwd]/$proj_dir/vitis_workspace"
set platform_name "zuboard_pwm_platform"
set app_name "pwm_app"

# Create Vitis TCL script for XSCT
set vitis_script "[pwd]/$proj_dir/create_vitis_project.tcl"
set vitis_fh [open $vitis_script w]

puts $vitis_fh "# Vitis XSCT Script - Auto-generated"
puts $vitis_fh "# Run with: xsct create_vitis_project.tcl"
puts $vitis_fh ""
puts $vitis_fh "set xsa_file \"$xsa_abs_path\""
puts $vitis_fh "set vitis_ws \"$vitis_ws\""
puts $vitis_fh "set platform_name \"$platform_name\""
puts $vitis_fh "set app_name \"$app_name\""
puts $vitis_fh ""
puts $vitis_fh "# Create workspace directory"
puts $vitis_fh "file mkdir \$vitis_ws"
puts $vitis_fh ""
puts $vitis_fh "# Set workspace"
puts $vitis_fh "setws \$vitis_ws"
puts $vitis_fh ""
puts $vitis_fh "# Create platform from XSA"
puts $vitis_fh "platform create -name \$platform_name -hw \$xsa_file -proc psu_cortexa53_0 -os standalone"
puts $vitis_fh ""
puts $vitis_fh "# Generate platform"
puts $vitis_fh "platform generate"
puts $vitis_fh ""
puts $vitis_fh "puts \"INFO: Platform created: \$platform_name\""
puts $vitis_fh ""
puts $vitis_fh "# Create application project"
puts $vitis_fh "app create -name \$app_name -platform \$platform_name -template \"Empty Application(C)\""
puts $vitis_fh ""
puts $vitis_fh "puts \"INFO: Application created: \$app_name\""
puts $vitis_fh ""
close $vitis_fh

# Create the PWM application source file
set app_src_dir "$vitis_ws/$app_name/src"
file mkdir $app_src_dir

# Create main.c with PWM code
set main_file "$app_src_dir/main.c"
set main_fh [open $main_file w]
puts $main_fh "/*"
puts $main_fh " * PWM Generation using PS MIO GPIO"
puts $main_fh " * ZUBoard 1CG - Zynq UltraScale+ MPSoC"
puts $main_fh " */"
puts $main_fh ""
puts $main_fh "#include <stdio.h>"
puts $main_fh "#include \"xparameters.h\""
puts $main_fh "#include \"xgpiops.h\""
puts $main_fh "#include \"sleep.h\""
puts $main_fh ""
puts $main_fh "#define GPIO_DEVICE_ID XPAR_XGPIOPS_0_DEVICE_ID"
puts $main_fh "#define MIO_PWM_PIN 26  // MIO pin for PWM output"
puts $main_fh ""
puts $main_fh "XGpioPs Gpio;"
puts $main_fh ""
puts $main_fh "void pwm_generate(u32 pin, u32 duty_cycle_us, u32 period_us, u32 duration_ms) {"
puts $main_fh "    u32 cycles = (duration_ms * 1000) / period_us;"
puts $main_fh "    u32 i;"
puts $main_fh "    "
puts $main_fh "    for (i = 0; i < cycles; i++) {"
puts $main_fh "        XGpioPs_WritePin(&Gpio, pin, 1);"
puts $main_fh "        usleep(duty_cycle_us);"
puts $main_fh "        XGpioPs_WritePin(&Gpio, pin, 0);"
puts $main_fh "        usleep(period_us - duty_cycle_us);"
puts $main_fh "    }"
puts $main_fh "}"
puts $main_fh ""
puts $main_fh "int main() {"
puts $main_fh "    XGpioPs_Config *ConfigPtr;"
puts $main_fh "    int Status;"
puts $main_fh "    "
puts $main_fh "    printf(\"PWM GPIO Test - ZUBoard 1CG\\r\\n\");"
puts $main_fh "    "
puts $main_fh "    // Initialize GPIO"
puts $main_fh "    ConfigPtr = XGpioPs_LookupConfig(GPIO_DEVICE_ID);"
puts $main_fh "    if (ConfigPtr == NULL) {"
puts $main_fh "        printf(\"GPIO Lookup Failed\\r\\n\");"
puts $main_fh "        return XST_FAILURE;"
puts $main_fh "    }"
puts $main_fh "    "
puts $main_fh "    Status = XGpioPs_CfgInitialize(&Gpio, ConfigPtr, ConfigPtr->BaseAddr);"
puts $main_fh "    if (Status != XST_SUCCESS) {"
puts $main_fh "        printf(\"GPIO Init Failed\\r\\n\");"
puts $main_fh "        return XST_FAILURE;"
puts $main_fh "    }"
puts $main_fh "    "
puts $main_fh "    // Set MIO pin as output"
puts $main_fh "    XGpioPs_SetDirectionPin(&Gpio, MIO_PWM_PIN, 1);"
puts $main_fh "    XGpioPs_SetOutputEnablePin(&Gpio, MIO_PWM_PIN, 1);"
puts $main_fh "    "
puts $main_fh "    printf(\"Generating PWM on MIO Pin %d\\r\\n\", MIO_PWM_PIN);"
puts $main_fh "    "
puts $main_fh "    // Generate PWM with different duty cycles"
puts $main_fh "    while(1) {"
puts $main_fh "        printf(\"25%% Duty Cycle\\r\\n\");"
puts $main_fh "        pwm_generate(MIO_PWM_PIN, 250, 1000, 2000);  // 25% duty, 1kHz, 2s"
puts $main_fh "        "
puts $main_fh "        printf(\"50%% Duty Cycle\\r\\n\");"
puts $main_fh "        pwm_generate(MIO_PWM_PIN, 500, 1000, 2000);  // 50% duty, 1kHz, 2s"
puts $main_fh "        "
puts $main_fh "        printf(\"75%% Duty Cycle\\r\\n\");"
puts $main_fh "        pwm_generate(MIO_PWM_PIN, 750, 1000, 2000);  // 75% duty, 1kHz, 2s"
puts $main_fh "    }"
puts $main_fh "    "
puts $main_fh "    return 0;"
puts $main_fh "}"
close $main_fh

puts "INFO: Application source created: $main_file"

# Append build command to Vitis script
set vitis_fh [open $vitis_script a]
puts $vitis_fh ""
puts $vitis_fh "# Build application"
puts $vitis_fh "app build -name \$app_name"
puts $vitis_fh ""
puts $vitis_fh "puts \"=========================================================================\""
puts $vitis_fh "puts \"Vitis Build Complete!\""
puts $vitis_fh "puts \"=========================================================================\""
puts $vitis_fh "puts \"Platform: \$platform_name\""
puts $vitis_fh "puts \"Application: \$app_name\""
puts $vitis_fh "puts \"ELF File: \$vitis_ws/\$app_name/Debug/\$app_name.elf\""
puts $vitis_fh "puts \"=========================================================================\""
puts $vitis_fh ""
puts $vitis_fh "exit"
close $vitis_fh

puts "INFO: Vitis script created: $vitis_script"

# Run XSCT to create Vitis project
puts "INFO: Running XSCT to create Vitis platform and application..."
if {[catch {exec xsct $vitis_script} result]} {
    puts "WARNING: XSCT execution result: $result"
} else {
    puts $result
}

puts "=========================================================================="
puts "Project Creation Complete!"
puts "=========================================================================="
puts "Project Name: $proj_name"
puts "Project Directory: $proj_dir"
puts "Target Device: $part_name"
puts "XSA File: $xsa_abs_path"
puts "Vitis Workspace: $vitis_ws"
puts "Platform: $platform_name"
puts "Application: $app_name"
puts ""
puts "To run manually if XSCT failed:"
puts "  cd $proj_dir && xsct create_vitis_project.tcl"
puts ""
puts "To program the board:"
puts "  xsct -eval \"connect; targets -set -filter {name =~ \\\"*A53*0\\\"}; dow $vitis_ws/$app_name/Debug/$app_name.elf; con\""
puts "=========================================================================="

exit