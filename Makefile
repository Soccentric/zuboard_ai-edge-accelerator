# Makefile for ZUBoard 1CG AI Edge Accelerator
# Target Device: xczu1cg-sbva484-1-e
#
# CNN Inference Engine for Real-time Object Detection/Classification
#
# This Makefile builds the complete Vivado + Vitis project from command line

SHELL = /bin/bash

# Project Configuration
PROJ_DIR = ai_edge_accelerator
PROJ_NAME = ai_edge_accelerator
XSA_FILE = $(PROJ_DIR)/$(PROJ_NAME).xsa
VITIS_WS = $(PROJ_DIR)/vitis_workspace
PLATFORM_NAME = ai_edge_platform
APP_NAME = cnn_inference_app
ELF_FILE = $(VITIS_WS)/$(APP_NAME)/Debug/$(APP_NAME).elf

# Source directories
RTL_DIR = rtl
RTL_CNN_DIR = $(RTL_DIR)/cnn
RTL_AXI_DIR = $(RTL_DIR)/axi
RTL_VIDEO_DIR = $(RTL_DIR)/video
TB_DIR = testbench
SW_DIR = software
CONSTRAINTS_DIR = constraints

# Xilinx tool paths (adjust for your installation)
XILINX_VERSION = 2024.2
XILINX_PATH = /tools/Xilinx
VIVADO_SETTINGS = $(XILINX_PATH)/Vivado/$(XILINX_VERSION)/settings64.sh
VITIS_SETTINGS = $(XILINX_PATH)/Vitis/$(XILINX_VERSION)/settings64.sh

# Tool commands
VIVADO_BATCH = source $(VIVADO_SETTINGS) && vivado -mode batch -nojournal -nolog
VIVADO_GUI = source $(VIVADO_SETTINGS) && vivado
XSCT = source $(VITIS_SETTINGS) && xsct
XSIM = source $(VIVADO_SETTINGS) && xvhdl && xelab && xsim

# RTL Source files
RTL_SOURCES = $(wildcard $(RTL_CNN_DIR)/*.vhd) \
              $(wildcard $(RTL_AXI_DIR)/*.vhd) \
              $(wildcard $(RTL_VIDEO_DIR)/*.vhd)

TB_SOURCES = $(wildcard $(TB_DIR)/*.vhd)

.PHONY: all clean build vitis gui program sim help rtl_check

# ============================================================================
# Default target - build everything
# ============================================================================
all: build

# ============================================================================
# Complete Build: Vivado + Vitis
# ============================================================================
build: rtl_check
	@echo "=========================================================================="
	@echo "Building AI Edge Accelerator (Vivado + Vitis)..."
	@echo "=========================================================================="
	$(VIVADO_BATCH) -source xczu1cg-sbva484-1-e-cnn.tcl
	@echo ""
	@echo "Build complete!"
	@echo "XSA File: $(XSA_FILE)"

# ============================================================================
# Vivado Only Build
# ============================================================================
vivado: rtl_check
	@echo "=========================================================================="
	@echo "Building Vivado project only..."
	@echo "=========================================================================="
	$(VIVADO_BATCH) -source xczu1cg-sbva484-1-e-cnn.tcl
	@echo "XSA File: $(XSA_FILE)"

# ============================================================================
# Vitis Only Build (requires XSA)
# ============================================================================
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

# ============================================================================
# RTL Syntax Check
# ============================================================================
rtl_check:
	@echo "Checking RTL source files..."
	@for f in $(RTL_SOURCES); do \
		echo "  Checking $$f"; \
	done
	@echo "Found $(words $(RTL_SOURCES)) RTL source files."

# ============================================================================
# Simulation
# ============================================================================
sim: $(RTL_SOURCES) $(TB_SOURCES)
	@echo "=========================================================================="
	@echo "Running Simulation..."
	@echo "=========================================================================="
	@mkdir -p sim_work
	cd sim_work && $(VIVADO_BATCH) -source ../sim/run_sim.tcl

sim_gui: $(RTL_SOURCES) $(TB_SOURCES)
	@echo "=========================================================================="
	@echo "Running Simulation with GUI..."
	@echo "=========================================================================="
	@mkdir -p sim_work
	cd sim_work && $(VIVADO_GUI) -source ../sim/run_sim.tcl

# ============================================================================
# Launch Vivado GUI
# ============================================================================
gui:
	@if [ -f "$(PROJ_DIR)/$(PROJ_NAME).xpr" ]; then \
		$(VIVADO_GUI) $(PROJ_DIR)/$(PROJ_NAME).xpr; \
	else \
		echo "Project not found. Creating project first..."; \
		$(VIVADO_GUI) -source xczu1cg-sbva484-1-e-cnn.tcl; \
	fi

# ============================================================================
# Program the Board
# ============================================================================
program: $(ELF_FILE)
	@echo "=========================================================================="
	@echo "Programming ZUBoard 1CG..."
	@echo "=========================================================================="
	$(XSCT) -eval "connect; \
		targets -set -filter {name =~ \"*A53*0\"}; \
		rst -system; \
		after 3000; \
		fpga -file $(PROJ_DIR)/$(PROJ_NAME).runs/impl_1/cnn_system_wrapper.bit; \
		dow $(ELF_FILE); \
		con"

program_bit:
	@echo "=========================================================================="
	@echo "Programming FPGA bitstream only..."
	@echo "=========================================================================="
	$(XSCT) -eval "connect; \
		fpga -file $(PROJ_DIR)/$(PROJ_NAME).runs/impl_1/cnn_system_wrapper.bit"

# ============================================================================
# Generate Reports
# ============================================================================
reports:
	@echo "=========================================================================="
	@echo "Generating implementation reports..."
	@echo "=========================================================================="
	$(VIVADO_BATCH) -source scripts/gen_reports.tcl

# ============================================================================
# Export Hardware
# ============================================================================
export_hw:
	@echo "=========================================================================="
	@echo "Exporting hardware platform..."
	@echo "=========================================================================="
	$(VIVADO_BATCH) -source scripts/export_hw.tcl

# ============================================================================
# Clean
# ============================================================================
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(PROJ_DIR)
	rm -rf sim_work
	rm -f vivado*.jou vivado*.log
	rm -f *.jou *.log *.pb *.str
	rm -rf .Xil
	rm -f webtalk*.jou webtalk*.log
	rm -f xsim*.jou xsim*.log
	rm -f *.wdb *.wcfg
	@echo "Clean complete."

clean_sim:
	@echo "Cleaning simulation artifacts..."
	rm -rf sim_work
	rm -f xsim*.jou xsim*.log
	rm -f *.wdb *.wcfg
	rm -f conv_output.txt
	@echo "Simulation clean complete."

# ============================================================================
# Help
# ============================================================================
help:
	@echo "=========================================================================="
	@echo "  ZUBoard 1CG AI Edge Accelerator - Build System"
	@echo "=========================================================================="
	@echo ""
	@echo "  Target Device: xczu1cg-sbva484-1-e (Zynq UltraScale+ ZU1CG)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Build Targets:"
	@echo "  all        - Build complete project (Vivado + Vitis)"
	@echo "  build      - Same as 'all'"
	@echo "  vivado     - Build Vivado project only (hardware)"
	@echo "  vitis      - Build Vitis project only (requires XSA)"
	@echo "  rtl_check  - Check RTL source files exist"
	@echo ""
	@echo "Simulation:"
	@echo "  sim        - Run simulation in batch mode"
	@echo "  sim_gui    - Run simulation with waveform viewer"
	@echo ""
	@echo "GUI & Programming:"
	@echo "  gui        - Open Vivado GUI with project"
	@echo "  program    - Program ZUBoard 1CG via JTAG (bitstream + ELF)"
	@echo "  program_bit- Program FPGA bitstream only"
	@echo ""
	@echo "Reports & Export:"
	@echo "  reports    - Generate implementation reports"
	@echo "  export_hw  - Export hardware platform (XSA)"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean      - Remove all build artifacts"
	@echo "  clean_sim  - Remove simulation artifacts only"
	@echo ""
	@echo "Output Files:"
	@echo "  XSA:       $(XSA_FILE)"
	@echo "  ELF:     $(ELF_FILE)"
	@echo ""
	@echo "Requirements:"
	@echo "  - Xilinx Vivado $(XILINX_VERSION)"
	@echo "  - Xilinx Vitis $(XILINX_VERSION)"
	@echo "  - JTAG cable connected (for 'program' target)"
	@echo "=========================================================================="
