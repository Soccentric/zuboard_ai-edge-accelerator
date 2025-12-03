# Makefile for ZUBoard 1CG PWM FPGA Project
# Target Device: xczu1cg-sbva484-1-e

# Vivado command with environment setup
VIVADO = bash -c "source /tools/Xilinx/Vivado/2024.2/settings64.sh && vivado"

.PHONY: all clean project synth impl bitstream help

# Default target
all: bitstream

# Create Vivado project
project:
	$(VIVADO) -mode batch -source xczu1cg-sbva484-1-e-pwm.tcl

# Run synthesis
synth: project
	$(VIVADO) -mode batch -source <(echo "open_project zuboard_pwm/zuboard_pwm_project.xpr; launch_runs synth_1; wait_on_run synth_1")

# Run implementation
impl: synth
	$(VIVADO) -mode batch -source <(echo "open_project zuboard_pwm/zuboard_pwm_project.xpr; launch_runs impl_1; wait_on_run impl_1")

# Generate bitstream
bitstream: impl
	$(VIVADO) -mode batch -source <(echo "open_project zuboard_pwm/zuboard_pwm_project.xpr; launch_runs impl_1 -to_step write_bitstream; wait_on_run impl_1")

# Clean build artifacts
clean:
	rm -rf zuboard_pwm
	rm -f vivado.jou vivado.log *.jou *log *.pb

# Display help
help:
	@echo "Available targets:"
	@echo "  all       - Build the complete project (default)"
	@echo "  project   - Create Vivado project"
	@echo "  synth     - Run synthesis"
	@echo "  impl      - Run implementation"
	@echo "  bitstream - Generate bitstream"
	@echo "  clean     - Remove build artifacts"
	@echo "  help      - Show this help message"
