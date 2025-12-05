# AI Edge Accelerator - CNN Inference Engine

## ZUBoard 1CG FPGA Project for Real-Time Object Detection and Classification

[![Target Device](https://img.shields.io/badge/Device-xczu1cg--sbva484--1--e-blue)](https://www.xilinx.com/products/silicon-devices/soc/zynq-ultrascale-mpsoc.html)
[![Board](https://img.shields.io/badge/Board-ZUBoard%201CG-green)](https://www.avnet.com/wps/portal/us/products/avnet-boards/avnet-board-families/zuboard-1cg/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 Overview

This project implements a **custom CNN (Convolutional Neural Network) inference engine** on the Zynq UltraScale+ ZU1CG FPGA. It is designed for **real-time object detection and image classification** at the edge, with camera input via DMA and optimized processing pipelines.

### Key Features

- 🧠 **Custom CNN Hardware Accelerator** - Conv2D, Pooling, Activation in RTL
- 📷 **Camera Input via DMA** - AXI-Stream interface for video frames
- ⚡ **Real-time Processing** - Designed for >30 FPS on 128x128 images
- 🔧 **Configurable Architecture** - Adjustable layers, filters, and parameters
- 📊 **Performance Counters** - Built-in cycle and operation counting
- 🔌 **AXI-Lite Control** - Easy software integration and configuration

---

## 🏗️ Architecture

### CNN Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AI Edge Accelerator System                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │ Camera  │───▶│ AXI DMA      │───▶│ Video Input  │───▶│ Conv2D #0    │   │
│  │ (MIPI)  │    │ Video        │    │ Preprocessor │    │ 3x3, 16 filt │   │
│  └─────────┘    └──────────────┘    └──────────────┘    └──────┬───────┘   │
│                                                                  │          │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────▼───────┐   │
│  │ PS      │───▶│ AXI-Lite     │───▶│ CNN Control  │    │ MaxPool #0   │   │
│  │ CPU     │    │ Interface    │    │ Registers    │    │ 2x2          │   │
│  └─────────┘    └──────────────┘    └──────────────┘    └──────┬───────┘   │
│                                                                  │          │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────▼───────┐   │
│  │ DDR4    │◀──▶│ AXI DMA      │◀───│ Result       │◀───│ Conv2D #1    │   │
│  │ Memory  │    │ Weights      │    │ Output       │    │ 3x3, 32 filt │   │
│  └─────────┘    └──────────────┘    └──────────────┘    └──────┬───────┘   │
│                                                                  │          │
│                                                          ┌──────▼───────┐   │
│                                                          │ MaxPool #1   │   │
│                                                          │ 2x2          │   │
│                                                          └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Video Input**: RGB frames from camera via AXI-Stream DMA
2. **Preprocessing**: RGB to fixed-point Q8.8 normalization
3. **Conv2D Layers**: 3x3 convolution with configurable filters
4. **Activation**: ReLU, Leaky ReLU, Sigmoid (LUT-based)
5. **Pooling**: 2x2 Max or Average pooling
6. **Output**: Classification probabilities

---

## 📁 Project Structure

```
zuboard_ai-edge-accelerator/
├── rtl/
│   ├── cnn/
│   │   ├── cnn_pkg.vhd              # CNN types and functions package
│   │   ├── cnn_accelerator_top.vhd  # Top-level accelerator module
│   │   ├── conv2d_engine.vhd        # 2D convolution with MAC array
│   │   ├── pooling_engine.vhd       # Max/Average pooling
│   │   ├── activation_unit.vhd      # Activation functions (LUT-based)
│   │   └── batchnorm_unit.vhd       # Batch normalization
│   ├── axi/
│   │   ├── axi_lite_cnn_ctrl.vhd    # Control/status registers
│   │   ├── axis_video_input.vhd     # Video stream input
│   │   └── axis_cnn_interconnect.vhd# Layer interconnect
│   └── video/
│       └── frame_buffer_ctrl.vhd    # Triple-buffered frame storage
├── software/
│   ├── include/
│   │   └── cnn_accelerator.h        # Driver header
│   └── src/
│       ├── cnn_accelerator.c        # Driver implementation
│       └── main.c                   # Demo application
├── testbench/
│   └── cnn_accelerator_tb.vhd       # VHDL testbench
├── constraints/
│   └── zuboard_cnn.xdc              # Timing constraints
├── models/
│   └── (pre-trained weights)        # Model weights in Q8.8 format
├── xczu1cg-sbva484-1-e-cnn.tcl      # Main Vivado build script
├── Makefile                         # Build automation
└── README.md                        # This file
```

---

## 🛠️ Requirements

### Hardware
- **Avnet ZUBoard 1CG** (xczu1cg-sbva484-1-e)
- USB JTAG programmer
- Optional: MIPI camera module

### Software
- **Xilinx Vivado 2024.2** (or compatible version)
- **Xilinx Vitis 2024.2**
- Linux/Windows with bash shell
- GNU Make

---

## 🚀 Quick Start

### 1. Clone and Setup

```bash
cd /path/to/workspace
git clone <repository-url>
cd zuboard_ai-edge-accelerator
```

### 2. Configure Environment

Source the Xilinx tools:

```bash
source source_me.vivado   # Vivado environment
source source_me.vitis    # Vitis environment
```

Or manually:

```bash
source /tools/Xilinx/Vivado/2024.2/settings64.sh
source /tools/Xilinx/Vitis/2024.2/settings64.sh
```

### 3. Build the Project

```bash
# Full build (Vivado + Vitis)
make build

# Or step by step:
make           # Build hardware only
make program   # Program the board
```

### 4. Simulation

```bash
make sim       # Run testbench simulation
```

---

## 📊 Register Map

The CNN accelerator is controlled via AXI-Lite registers at base address `0x80000000`:

| Offset | Name | Description |
|--------|------|-------------|
| 0x00 | CONTROL | Start/Stop/Reset control bits |
| 0x04 | STATUS | Busy/Done/Error status |
| 0x08 | CONFIG | Layer enable, activation, pooling |
| 0x0C | LAYER_CONFIG | Number of input/output channels |
| 0x10 | INPUT_ADDR | DMA address for input frame |
| 0x14 | OUTPUT_ADDR | DMA address for results |
| 0x18 | WEIGHT_ADDR | DMA address for weights |
| 0x1C | BIAS_ADDR | DMA address for biases |
| 0x20 | IRQ_ENABLE | Interrupt enable mask |
| 0x24 | IRQ_STATUS | Interrupt status (W1C) |
| 0x28 | RESULT_0/1 | Top classification results |
| 0x30 | PERF_CYCLES | Performance counter: cycles |
| 0x34 | PERF_OPS | Performance counter: MACs |

### Control Register (0x00)
- Bit 0: `START` - Begin inference
- Bit 1: `STOP` - Abort operation
- Bit 2: `RESET` - Soft reset

### Status Register (0x04)
- Bit 0: `BUSY` - Inference in progress
- Bit 1: `DONE` - Inference complete
- Bit 2: `ERROR` - Error occurred
- Bits 7:4: `STATE` - State machine state

---

## 💻 Software API

### Basic Usage

```c
#include "cnn_accelerator.h"

int main() {
    CNN_Accelerator cnn;
    
    // Initialize with base address
    CNN_Init(&cnn, CNN_BASEADDR);
    
    // Load pre-trained weights
    CNN_LoadWeights(&cnn, weights_data, NUM_WEIGHTS);
    CNN_LoadBiases(&cnn, biases_data, NUM_BIASES);
    
    // Configure for inference
    CNN_SetInputAddress(&cnn, input_frame_addr);
    CNN_SetOutputAddress(&cnn, output_buffer_addr);
    
    // Start inference
    CNN_Start(&cnn);
    
    // Wait for completion
    while (!CNN_IsDone(&cnn)) {
        // Optionally do other work
    }
    
    // Get classification result
    uint32_t class_id = CNN_GetTopClass(&cnn);
    uint32_t confidence = CNN_GetConfidence(&cnn);
    
    printf("Detected class %d with confidence %d%%\n", 
           class_id, confidence);
    
    return 0;
}
```

### API Reference

| Function | Description |
|----------|-------------|
| `CNN_Init()` | Initialize accelerator driver |
| `CNN_Reset()` | Soft reset the accelerator |
| `CNN_LoadWeights()` | Load convolution weights |
| `CNN_LoadBiases()` | Load bias values |
| `CNN_SetInputAddress()` | Set DMA input buffer |
| `CNN_SetOutputAddress()` | Set DMA output buffer |
| `CNN_Start()` | Begin inference |
| `CNN_IsDone()` | Check completion status |
| `CNN_GetTopClass()` | Get top classification |
| `CNN_GetConfidence()` | Get confidence score |
| `CNN_GetCycleCount()` | Get performance cycles |

---

## ⚙️ Configuration

### Activation Functions

The accelerator supports multiple activation functions selectable via register:

| Value | Function | Formula |
|-------|----------|---------|
| 0 | None | `y = x` |
| 1 | ReLU | `y = max(0, x)` |
| 2 | Leaky ReLU | `y = x > 0 ? x : 0.1*x` |
| 3 | Sigmoid | `y = 1/(1+exp(-x))` [LUT] |

### Fixed-Point Format

All internal computations use **Q8.8 fixed-point**:
- 8 bits signed integer part
- 8 bits fractional part
- Range: -128.0 to +127.996
- Resolution: 0.00390625

Convert float to Q8.8: `int16_t q88 = (int16_t)(float_val * 256.0f);`

---

## 📈 Performance Estimates

### Resource Utilization

| Resource | Used | Available | % |
|----------|------|-----------|---|
| LUTs | ~15,000 | 37,440 | 40% |
| FFs | ~12,000 | 74,880 | 16% |
| BRAMs | ~30 | 216 | 14% |
| DSP48s | ~50 | 120 | 42% |

### Throughput

- **Clock Frequency**: 100 MHz
- **Inference Latency**: ~2ms (128x128x3 input)
- **Peak Throughput**: 500+ FPS (memory limited)
- **MAC Operations**: 3.2 GOPS

---

## 🧪 Testing

### Run Testbench

```bash
# Batch simulation
make sim

# GUI simulation (waveforms)
make sim_gui
```

### Expected Output

```
========================================
  CNN Accelerator Testbench Starting   
========================================
Loading weights...
Weights loaded: 5040 values
Starting inference...
Inference complete: 15234 cycles
Top class: 3, Confidence: 92%
========================================
  TEST PASSED
========================================
```

---

## 🐛 Troubleshooting

### Build Issues

**"Board part not found"**
- Install ZUBoard board files from Avnet website
- Place in `~/.Xilinx/Vivado/2024.2/board_files/`

**Timing violations**
- Reduce `C_AXI_CLK_FREQ_HZ` in TCL script
- Check synthesis report for critical paths

### Runtime Issues

**Inference hangs**
- Verify DMA addresses are 64-byte aligned
- Check `STATUS` register for error flags
- Ensure weights are loaded before starting

**Wrong classification**
- Verify weight format is Q8.8 signed
- Check input normalization (0-255 → Q8.8)
- Validate model against software reference

---

## 🗺️ Roadmap

- [ ] Add depthwise separable convolution
- [ ] INT8 quantization support
- [ ] MIPI CSI-2 camera interface
- [ ] YOLO-style detection output
- [ ] ONNX model converter
- [ ] Batch processing mode

---

## 📚 References

- [Zynq UltraScale+ MPSoC Technical Reference Manual (UG1085)](https://docs.xilinx.com/r/en-US/ug1085-zynq-ultrascale-trm)
- [Vivado Design Suite User Guide (UG910)](https://docs.xilinx.com/r/en-US/ug910-vivado-getting-started)
- [AXI Reference Guide (UG1037)](https://docs.xilinx.com/r/en-US/ug1037-vivado-axi-reference-guide)

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
