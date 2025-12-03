# Makefile for ZUBoard 1CG PWM FPGA Project
# Target Device: xczu1cg-sbva484-1-e

SHELL = /bin/bash

# Vivado command with environment setup
VIVADO_BATCH = source /tools/Xilinx/Vivado/2024.2/settings64.sh && vivado -mode batch -source
VIVADO_GUI = bash -c "source /tools/Xilinx/Vivado/2024.2/settings64.sh && vivado"

.PHONY: all clean project synth impl bitstream xsa gui help

# Default target
all: xsa

# Create Vivado project
project:
	$(VIVADO_BATCH) xczu1cg-sbva484-1-e-pwm.tcl

# Run synthesis
synth: project
	@echo 'open_project zuboard_pwm/zuboard_pwm_project.xpr' > run_synth.tcl
	@echo 'reset_run synth_1' >> run_synth.tcl
	@echo 'launch_runs synth_1 -jobs 4' >> run_synth.tcl
	@echo 'wait_on_run synth_1' >> run_synth.tcl
	$(VIVADO_BATCH) run_synth.tcl
	@rm -f run_synth.tcl

# Run implementation
impl: synth
	@echo 'open_project zuboard_pwm/zuboard_pwm_project.xpr' > run_impl.tcl
	@echo 'reset_run impl_1' >> run_impl.tcl
	@echo 'launch_runs impl_1 -jobs 4' >> run_impl.tcl
	@echo 'wait_on_run impl_1' >> run_impl.tcl
	$(VIVADO_BATCH) run_impl.tcl
	@rm -f run_impl.tcl

# Generate bitstream
bitstream: impl
	@echo 'open_project zuboard_pwm/zuboard_pwm_project.xpr' > run_bitstream.tcl
	@echo 'launch_runs impl_1 -to_step write_bitstream -jobs 4' >> run_bitstream.tcl
	@echo 'wait_on_run impl_1' >> run_bitstream.tcl
	$(VIVADO_BATCH) run_bitstream.tcl
	@rm -f run_bitstream.tcl

# Export hardware (XSA file) for Vitis
xsa: bitstream
	@echo 'open_project zuboard_pwm/zuboard_pwm_project.xpr' > run_export.tcl
	@echo 'open_run impl_1' >> run_export.tcl
	@echo 'write_hw_platform -fixed -include_bit -force -file zuboard_pwm/pwm_design_wrapper.xsa' >> run_export.tcl
	$(VIVADO_BATCH) run_export.tcl
	@rm -f run_export.tcl
	@echo "XSA file generated: zuboard_pwm/pwm_design_wrapper.xsa"

# Launch Vivado GUI with the project
gui: project
	$(VIVADO_GUI) zuboard_pwm/zuboard_pwm_project.xpr

# Clean build artifacts
clean:
	rm -rf zuboard_pwm
	rm -f vivado.jou vivado.log *.jou *.log *.pb *.str run_*.tcl

# Display help
help:
	@echo "Available targets:"
	@echo "  all       - Build the complete project including XSA (default)"
	@echo "  project   - Create Vivado project"
	@echo "  synth     - Run synthesis"
	@echo "  impl      - Run implementation"
	@echo "  bitstream - Generate bitstream"
	@echo "  xsa       - Export hardware XSA file for Vitis"
	@echo "  gui       - Launch Vivado GUI with the project"
	@echo "  clean     - Remove build artifacts"
	@echo "  help      - Show this help message"
