# Makefile for ZUBoard 1CG PWM FPGA Project
# Target Device: xczu1cg-sbva484-1-e
#
# This Makefile builds the complete Vivado + Vitis project from command line (no GUI)

SHELL = /bin/bash

# Project directories and files
PROJ_DIR = zuboard_pwm
PROJ_NAME = zuboard_pwm_project
XSA_FILE = $(PROJ_DIR)/$(PROJ_NAME).xsa
VITIS_WS = $(PROJ_DIR)/vitis_workspace
PLATFORM_NAME = zuboard_pwm_platform
APP_NAME = pwm_app
ELF_FILE = $(VITIS_WS)/$(APP_NAME)/Debug/$(APP_NAME).elf

# Xilinx tool paths (adjust for your installation)
XILINX_VERSION = 2024.2
XILINX_PATH = /tools/Xilinx
VIVADO_SETTINGS = $(XILINX_PATH)/Vivado/$(XILINX_VERSION)/settings64.sh
VITIS_SETTINGS = $(XILINX_PATH)/Vitis/$(XILINX_VERSION)/settings64.sh

# Tool commands
VIVADO_BATCH = source $(VIVADO_SETTINGS) && vivado -mode batch -nojournal -nolog
VIVADO_GUI = source $(VIVADO_SETTINGS) && vivado
XSCT = source $(VITIS_SETTINGS) && xsct

.PHONY: all clean build vitis gui program help

# Default target - build everything (Vivado + Vitis)
all: build

# Complete build: Vivado project, synthesis, implementation, bitstream, XSA, and Vitis application
build:
	@echo "=========================================================================="
	@echo "Building complete project (Vivado + Vitis)..."
	@echo "=========================================================================="
	$(VIVADO_BATCH) -source xczu1cg-sbva484-1-e-pwm.tcl
	@echo ""
	@echo "Build complete!"
	@echo "XSA File: $(XSA_FILE)"
	@echo "ELF File: $(ELF_FILE)"

# Build only Vitis project (requires XSA to exist)
vitis: $(XSA_FILE)
	@echo "=========================================================================="
	@echo "Building Vitis platform and application..."
	@echo "=========================================================================="
	@if [ -f "$(PROJ_DIR)/create_vitis_project.tcl" ]; then \
		cd $(PROJ_DIR) && $(XSCT) create_vitis_project.tcl; \
	else \
		echo "ERROR: Vitis script not found. Run 'make build' first."; \
		exit 1; \
	fi

# Launch Vivado GUI with the project
gui:
	@if [ -f "$(PROJ_DIR)/$(PROJ_NAME).xpr" ]; then \
		$(VIVADO_GUI) $(PROJ_DIR)/$(PROJ_NAME).xpr; \
	else \
		echo "Project not found. Creating project first..."; \
		$(VIVADO_GUI) -source xczu1cg-sbva484-1-e-pwm.tcl; \
	fi

# Program the board via JTAG
program: $(ELF_FILE)
	@echo "=========================================================================="
	@echo "Programming ZUBoard 1CG..."
	@echo "=========================================================================="
	$(XSCT) -eval "connect; targets -set -filter {name =~ \"*A53*0\"}; dow $(ELF_FILE); con"

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(PROJ_DIR)
	rm -f vivado*.jou vivado*.log
	rm -f *.jou *.log *.pb *.str
	rm -f .Xil -rf
	rm -f run_*.tcl
	@echo "Clean complete."

# Display help
help:
	@echo "=========================================================================="
	@echo "ZUBoard 1CG PWM Project - Makefile Help"
	@echo "=========================================================================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build complete project: Vivado + Vitis (default)"
	@echo "  build    - Same as 'all' - full build from TCL script"
	@echo "  vitis    - Build only Vitis project (requires existing XSA)"
	@echo "  gui      - Launch Vivado GUI with the project"
	@echo "  program  - Program the ZUBoard 1CG via JTAG"
	@echo "  clean    - Remove all build artifacts"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Output files:"
	@echo "  XSA:     $(XSA_FILE)"
	@echo "  ELF:     $(ELF_FILE)"
	@echo ""
	@echo "Requirements:"
	@echo "  - Xilinx Vivado $(XILINX_VERSION)"
	@echo "  - Xilinx Vitis $(XILINX_VERSION)"
	@echo "  - JTAG cable connected (for 'program' target)"
	@echo "=========================================================================="
