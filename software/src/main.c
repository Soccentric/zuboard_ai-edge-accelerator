/*
 * AI Edge Accelerator - Main Application
 * Real-time CNN Inference Demo for ZUBoard 1CG
 * 
 * This demo application:
 *   1. Initializes the CNN accelerator hardware
 *   2. Loads pre-trained weights for image classification
 *   3. Processes input frames from DMA (simulated camera)
 *   4. Outputs classification results
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "sleep.h"

#include "cnn_accelerator.h"

/* ============================================================================
 * Configuration
 * ============================================================================ */

#define INPUT_WIDTH         128
#define INPUT_HEIGHT        128
#define INPUT_CHANNELS      3
#define NUM_CLASSES         10

/* Frame buffer addresses */
#define FRAME_BUFFER_ADDR   0x20000000
#define WEIGHT_BUFFER_ADDR  0x10000000
#define BIAS_BUFFER_ADDR    0x18000000
#define RESULT_BUFFER_ADDR  0x28000000

/* Test pattern types */
typedef enum {
    PATTERN_GRADIENT = 0,
    PATTERN_CHECKERBOARD,
    PATTERN_NOISE,
    PATTERN_SOLID
} TestPattern_t;

/* Class labels (example: CIFAR-10 like) */
static const char *class_labels[NUM_CLASSES] = {
    "airplane",
    "automobile", 
    "bird",
    "cat",
    "deer",
    "dog",
    "frog",
    "horse",
    "ship",
    "truck"
};

/* ============================================================================
 * Global Variables
 * ============================================================================ */

static CnnAccelerator_t cnn;

/* ============================================================================
 * Helper Functions
 * ============================================================================ */

/**
 * Generate test frame with specified pattern
 */
void GenerateTestFrame(uint8_t *buffer, int width, int height, TestPattern_t pattern)
{
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int idx = (y * width + x) * 3;  /* RGB */
            
            switch (pattern) {
                case PATTERN_GRADIENT:
                    buffer[idx + 0] = (x * 255) / width;      /* R: horizontal gradient */
                    buffer[idx + 1] = (y * 255) / height;     /* G: vertical gradient */
                    buffer[idx + 2] = 128;                     /* B: constant */
                    break;
                    
                case PATTERN_CHECKERBOARD:
                    if (((x / 16) + (y / 16)) % 2 == 0) {
                        buffer[idx + 0] = 255;
                        buffer[idx + 1] = 255;
                        buffer[idx + 2] = 255;
                    } else {
                        buffer[idx + 0] = 0;
                        buffer[idx + 1] = 0;
                        buffer[idx + 2] = 0;
                    }
                    break;
                    
                case PATTERN_NOISE:
                    buffer[idx + 0] = rand() % 256;
                    buffer[idx + 1] = rand() % 256;
                    buffer[idx + 2] = rand() % 256;
                    break;
                    
                case PATTERN_SOLID:
                default:
                    buffer[idx + 0] = 128;
                    buffer[idx + 1] = 128;
                    buffer[idx + 2] = 128;
                    break;
            }
        }
    }
}

/**
 * Generate random weights for testing (would be replaced with trained weights)
 */
void GenerateTestWeights(int16_t *weights, uint32_t count)
{
    /* Generate small random weights in Q8.8 format */
    for (uint32_t i = 0; i < count; i++) {
        /* Random value between -0.5 and 0.5 in Q8.8 (-128 to 128) */
        weights[i] = (int16_t)((rand() % 256) - 128);
    }
}

/**
 * Generate random biases for testing
 */
void GenerateTestBiases(int16_t *biases, uint32_t count)
{
    for (uint32_t i = 0; i < count; i++) {
        /* Small bias values */
        biases[i] = (int16_t)((rand() % 64) - 32);
    }
}

/**
 * Print CNN status
 */
void PrintStatus(CnnAccelerator_t *cnn)
{
    CnnStatus_t status;
    CNN_GetStatus(cnn, &status);
    
    xil_printf("CNN Status:\r\n");
    xil_printf("  Busy: %s\r\n", status.busy ? "Yes" : "No");
    xil_printf("  Done: %s\r\n", status.done ? "Yes" : "No");
    xil_printf("  Error: %d\r\n", status.error_code);
    xil_printf("  Cycles: %lu\r\n", status.cycles);
    xil_printf("  Operations: %lu\r\n", status.operations);
    
    if (status.cycles > 0) {
        float mops = (float)status.operations / (float)status.cycles;
        xil_printf("  MOPS/cycle: %.2f\r\n", mops);
    }
}

/**
 * Print inference results
 */
void PrintResults(InferenceResult_t *result)
{
    xil_printf("\r\n=== Classification Results ===\r\n");
    
    for (int i = 0; i < result->num_results; i++) {
        int class_id = result->classifications[i].class_id;
        float conf = result->classifications[i].confidence;
        
        xil_printf("  %d. %s: %.2f%%\r\n", 
                   i + 1,
                   (class_id < NUM_CLASSES) ? class_labels[class_id] : "unknown",
                   conf * 100.0f);
    }
    xil_printf("==============================\r\n");
}

/**
 * Run single inference benchmark
 */
void RunInferenceBenchmark(CnnAccelerator_t *cnn, int num_iterations)
{
    xil_printf("\r\n--- Running Inference Benchmark (%d iterations) ---\r\n", num_iterations);
    
    uint32_t total_cycles = 0;
    uint32_t total_ops = 0;
    
    for (int i = 0; i < num_iterations; i++) {
        /* Start inference */
        if (CNN_StartInference(cnn, FRAME_BUFFER_ADDR) != XST_SUCCESS) {
            xil_printf("ERROR: Failed to start inference %d\r\n", i);
            continue;
        }
        
        /* Wait for completion */
        if (CNN_WaitForCompletion(cnn, 5000) != XST_SUCCESS) {
            xil_printf("ERROR: Inference %d timed out\r\n", i);
            CNN_Reset(cnn);
            continue;
        }
        
        /* Accumulate stats */
        CnnStatus_t status;
        CNN_GetStatus(cnn, &status);
        total_cycles += status.cycles;
        total_ops += status.operations;
        
        if ((i + 1) % 10 == 0) {
            xil_printf("  Completed %d iterations\r\n", i + 1);
        }
    }
    
    /* Print summary */
    xil_printf("\r\nBenchmark Summary:\r\n");
    xil_printf("  Total iterations: %d\r\n", num_iterations);
    xil_printf("  Total cycles: %lu\r\n", total_cycles);
    xil_printf("  Total operations: %lu\r\n", total_ops);
    
    if (num_iterations > 0) {
        float avg_cycles = (float)total_cycles / num_iterations;
        float avg_ops = (float)total_ops / num_iterations;
        
        xil_printf("  Avg cycles/frame: %.0f\r\n", avg_cycles);
        xil_printf("  Avg ops/frame: %.0f\r\n", avg_ops);
        
        /* Assuming 100MHz clock */
        float frame_time_ms = avg_cycles / 100000.0f;  /* 100MHz = 100000 cycles/ms */
        float fps = 1000.0f / frame_time_ms;
        
        xil_printf("  Est. frame time: %.2f ms\r\n", frame_time_ms);
        xil_printf("  Est. FPS: %.1f\r\n", fps);
    }
}

/* ============================================================================
 * Main Application
 * ============================================================================ */

int main()
{
    int status;
    
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("  AI Edge Accelerator - CNN Inference   \r\n");
    xil_printf("  ZUBoard 1CG Demo Application          \r\n");
    xil_printf("========================================\r\n");
    xil_printf("\r\n");
    
    /* Initialize caches */
    Xil_DCacheEnable();
    Xil_ICacheEnable();
    
    /* ========================================================================
     * Step 1: Initialize CNN Accelerator
     * ======================================================================== */
    xil_printf("Initializing CNN Accelerator...\r\n");
    
    status = CNN_Init(&cnn);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to initialize CNN accelerator!\r\n");
        return XST_FAILURE;
    }
    xil_printf("  CNN Accelerator initialized successfully.\r\n");
    
    /* ========================================================================
     * Step 2: Configure CNN
     * ======================================================================== */
    xil_printf("Configuring CNN...\r\n");
    
    CnnConfig_t config;
    config.input_width = INPUT_WIDTH;
    config.input_height = INPUT_HEIGHT;
    config.input_channels = INPUT_CHANNELS;
    config.num_classes = NUM_CLASSES;
    config.layer_enable = 0x0F;         /* Enable first 4 layers */
    config.activation = CNN_ACT_RELU;
    config.pool_type = CNN_POOL_MAX;
    
    status = CNN_Configure(&cnn, &config);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to configure CNN!\r\n");
        return XST_FAILURE;
    }
    xil_printf("  Input: %dx%dx%d\r\n", INPUT_WIDTH, INPUT_HEIGHT, INPUT_CHANNELS);
    xil_printf("  Classes: %d\r\n", NUM_CLASSES);
    xil_printf("  Activation: ReLU\r\n");
    xil_printf("  Pooling: Max\r\n");
    
    /* ========================================================================
     * Step 3: Load Weights and Biases
     * ======================================================================== */
    xil_printf("Loading weights and biases...\r\n");
    
    /* Calculate weight sizes for simple 2-layer CNN:
     * Conv0: 3x3x3x16 = 432 weights + 16 biases
     * Conv1: 3x3x16x32 = 4608 weights + 32 biases
     */
    uint32_t total_weights = 432 + 4608;
    uint32_t total_biases = 16 + 32;
    
    int16_t *weights = (int16_t *)WEIGHT_BUFFER_ADDR;
    int16_t *biases = (int16_t *)BIAS_BUFFER_ADDR;
    
    /* Generate test weights (in real application, load from file/flash) */
    xil_printf("  Generating test weights (%lu values)...\r\n", total_weights);
    GenerateTestWeights(weights, total_weights);
    
    xil_printf("  Generating test biases (%lu values)...\r\n", total_biases);
    GenerateTestBiases(biases, total_biases);
    
    /* Load to accelerator */
    status = CNN_LoadWeights(&cnn, weights, total_weights * sizeof(int16_t));
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to load weights!\r\n");
        return XST_FAILURE;
    }
    
    status = CNN_LoadBiases(&cnn, biases, total_biases * sizeof(int16_t));
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to load biases!\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("  Weights and biases loaded successfully.\r\n");
    
    /* ========================================================================
     * Step 4: Generate Test Frame
     * ======================================================================== */
    xil_printf("Generating test frame...\r\n");
    
    uint8_t *frame_buffer = (uint8_t *)FRAME_BUFFER_ADDR;
    GenerateTestFrame(frame_buffer, INPUT_WIDTH, INPUT_HEIGHT, PATTERN_GRADIENT);
    
    /* Flush cache to ensure data is in memory */
    Xil_DCacheFlushRange(FRAME_BUFFER_ADDR, INPUT_WIDTH * INPUT_HEIGHT * 3);
    
    xil_printf("  Test frame generated at 0x%08X\r\n", FRAME_BUFFER_ADDR);
    
    /* ========================================================================
     * Step 5: Run Inference
     * ======================================================================== */
    xil_printf("\r\nStarting inference...\r\n");
    
    status = CNN_StartInference(&cnn, FRAME_BUFFER_ADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to start inference!\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("  Inference started, waiting for completion...\r\n");
    
    /* Wait for completion with timeout */
    status = CNN_WaitForCompletion(&cnn, 10000);  /* 10 second timeout */
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Inference timed out!\r\n");
        PrintStatus(&cnn);
        return XST_FAILURE;
    }
    
    xil_printf("  Inference completed!\r\n");
    
    /* Print status */
    PrintStatus(&cnn);
    
    /* ========================================================================
     * Step 6: Get Results
     * ======================================================================== */
    InferenceResult_t result;
    status = CNN_GetResult(&cnn, &result);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to get results!\r\n");
        return XST_FAILURE;
    }
    
    PrintResults(&result);
    
    /* ========================================================================
     * Step 7: Run Benchmark (optional)
     * ======================================================================== */
    xil_printf("\r\nWould you like to run benchmark? Running 100 iterations...\r\n");
    RunInferenceBenchmark(&cnn, 100);
    
    /* ========================================================================
     * Done
     * ======================================================================== */
    xil_printf("\r\n========================================\r\n");
    xil_printf("  Demo completed successfully!          \r\n");
    xil_printf("========================================\r\n");
    
    /* Continuous inference loop (for real-time demo) */
    xil_printf("\r\nEntering continuous inference mode...\r\n");
    xil_printf("Press Ctrl+C to stop.\r\n\r\n");
    
    int frame_count = 0;
    while (1) {
        /* Generate new test frame with different pattern */
        TestPattern_t pattern = (TestPattern_t)(frame_count % 4);
        GenerateTestFrame(frame_buffer, INPUT_WIDTH, INPUT_HEIGHT, pattern);
        Xil_DCacheFlushRange(FRAME_BUFFER_ADDR, INPUT_WIDTH * INPUT_HEIGHT * 3);
        
        /* Run inference */
        CNN_StartInference(&cnn, FRAME_BUFFER_ADDR);
        CNN_WaitForCompletion(&cnn, 5000);
        
        /* Get and display result */
        CNN_GetResult(&cnn, &result);
        
        xil_printf("Frame %d: Top prediction = %s (%.1f%%)\r\n",
                   frame_count,
                   (result.classifications[0].class_id < NUM_CLASSES) ?
                       class_labels[result.classifications[0].class_id] : "unknown",
                   result.classifications[0].confidence * 100.0f);
        
        frame_count++;
        
        /* Small delay between frames */
        usleep(100000);  /* 100ms = 10 FPS target */
    }
    
    return XST_SUCCESS;
}
