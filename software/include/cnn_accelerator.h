/*
 * CNN Accelerator Driver Header
 * AI Edge Accelerator for ZUBoard 1CG
 * 
 * This driver provides functions to:
 *   - Initialize and configure the CNN accelerator
 *   - Load weights and biases
 *   - Process frames for inference
 *   - Get classification/detection results
 */

#ifndef CNN_ACCELERATOR_H
#define CNN_ACCELERATOR_H

#include <stdint.h>
#include "xil_types.h"
#include "xstatus.h"

/* ============================================================================
 * Hardware Address Definitions
 * ============================================================================ */

#define CNN_ACCEL_BASE_ADDR     0x80000000
#define DMA_VIDEO_BASE_ADDR     0x80010000
#define DMA_WEIGHTS_BASE_ADDR   0x80020000
#define INTC_BASE_ADDR          0x80030000

/* ============================================================================
 * CNN Accelerator Register Map
 * ============================================================================ */

/* Register offsets */
#define CNN_REG_CONTROL         0x00
#define CNN_REG_STATUS          0x04
#define CNN_REG_CONFIG          0x08
#define CNN_REG_INPUT_DIM       0x0C
#define CNN_REG_WEIGHT_ADDR     0x10
#define CNN_REG_BIAS_ADDR       0x14
#define CNN_REG_INPUT_ADDR      0x18
#define CNN_REG_OUTPUT_ADDR     0x1C
#define CNN_REG_IRQ_ENABLE      0x20
#define CNN_REG_IRQ_STATUS      0x24
#define CNN_REG_PERF_CYCLES     0x28
#define CNN_REG_PERF_OPS        0x2C

/* Control register bits */
#define CNN_CTRL_START          0x01
#define CNN_CTRL_STOP           0x02
#define CNN_CTRL_RESET          0x04

/* Status register bits */
#define CNN_STAT_BUSY           0x01
#define CNN_STAT_DONE           0x02
#define CNN_STAT_ERROR_MASK     0xF0

/* Config register bits */
#define CNN_CFG_LAYER_EN_MASK   0x000000FF
#define CNN_CFG_ACT_MASK        0x00000700
#define CNN_CFG_ACT_SHIFT       8
#define CNN_CFG_POOL_TYPE       0x00000800

/* Interrupt bits */
#define CNN_IRQ_DONE            0x01
#define CNN_IRQ_ERROR           0x02

/* ============================================================================
 * Activation Functions
 * ============================================================================ */

typedef enum {
    CNN_ACT_NONE = 0,
    CNN_ACT_RELU = 1,
    CNN_ACT_RELU6 = 2,
    CNN_ACT_LEAKY_RELU = 3,
    CNN_ACT_SIGMOID = 4,
    CNN_ACT_TANH = 5,
    CNN_ACT_SWISH = 6
} CnnActivation_t;

/* ============================================================================
 * Pooling Types
 * ============================================================================ */

typedef enum {
    CNN_POOL_MAX = 0,
    CNN_POOL_AVG = 1
} CnnPoolType_t;

/* ============================================================================
 * CNN Configuration Structure
 * ============================================================================ */

typedef struct {
    uint16_t input_width;
    uint16_t input_height;
    uint8_t input_channels;
    uint8_t num_classes;
    uint8_t layer_enable;       /* Bitmask for enabled layers */
    CnnActivation_t activation;
    CnnPoolType_t pool_type;
} CnnConfig_t;

/* ============================================================================
 * CNN Status Structure
 * ============================================================================ */

typedef struct {
    uint8_t busy;
    uint8_t done;
    uint8_t error_code;
    uint32_t cycles;
    uint32_t operations;
} CnnStatus_t;

/* ============================================================================
 * Inference Result Structure
 * ============================================================================ */

#define CNN_MAX_CLASSES     100
#define CNN_MAX_DETECTIONS  20

typedef struct {
    int class_id;
    float confidence;
} ClassificationResult_t;

typedef struct {
    int class_id;
    float confidence;
    float x_min;
    float y_min;
    float x_max;
    float y_max;
} DetectionResult_t;

typedef struct {
    int num_results;
    union {
        ClassificationResult_t classifications[CNN_MAX_CLASSES];
        DetectionResult_t detections[CNN_MAX_DETECTIONS];
    };
} InferenceResult_t;

/* ============================================================================
 * CNN Accelerator Handle
 * ============================================================================ */

typedef struct {
    uint32_t base_addr;
    uint32_t dma_video_addr;
    uint32_t dma_weights_addr;
    CnnConfig_t config;
    uint32_t weight_mem_addr;
    uint32_t bias_mem_addr;
    uint32_t input_frame_addr;
    uint32_t output_result_addr;
    volatile int inference_done;
} CnnAccelerator_t;

/* ============================================================================
 * Function Prototypes
 * ============================================================================ */

/**
 * Initialize the CNN accelerator
 * @param cnn Pointer to CNN accelerator handle
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_Init(CnnAccelerator_t *cnn);

/**
 * Configure the CNN accelerator
 * @param cnn Pointer to CNN accelerator handle
 * @param config Pointer to configuration structure
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_Configure(CnnAccelerator_t *cnn, const CnnConfig_t *config);

/**
 * Reset the CNN accelerator
 * @param cnn Pointer to CNN accelerator handle
 */
void CNN_Reset(CnnAccelerator_t *cnn);

/**
 * Load weights from memory to accelerator
 * @param cnn Pointer to CNN accelerator handle
 * @param weights Pointer to weight data
 * @param size Size of weight data in bytes
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_LoadWeights(CnnAccelerator_t *cnn, const int16_t *weights, uint32_t size);

/**
 * Load biases from memory to accelerator
 * @param cnn Pointer to CNN accelerator handle
 * @param biases Pointer to bias data
 * @param size Size of bias data in bytes
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_LoadBiases(CnnAccelerator_t *cnn, const int16_t *biases, uint32_t size);

/**
 * Start inference on a frame (non-blocking)
 * @param cnn Pointer to CNN accelerator handle
 * @param frame_addr Address of input frame in memory
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_StartInference(CnnAccelerator_t *cnn, uint32_t frame_addr);

/**
 * Wait for inference to complete
 * @param cnn Pointer to CNN accelerator handle
 * @param timeout_ms Timeout in milliseconds (0 = infinite)
 * @return XST_SUCCESS or XST_FAILURE (timeout)
 */
int CNN_WaitForCompletion(CnnAccelerator_t *cnn, uint32_t timeout_ms);

/**
 * Check if inference is complete (non-blocking)
 * @param cnn Pointer to CNN accelerator handle
 * @return 1 if complete, 0 if still running
 */
int CNN_IsComplete(CnnAccelerator_t *cnn);

/**
 * Get inference results
 * @param cnn Pointer to CNN accelerator handle
 * @param result Pointer to result structure
 * @return XST_SUCCESS or XST_FAILURE
 */
int CNN_GetResult(CnnAccelerator_t *cnn, InferenceResult_t *result);

/**
 * Get accelerator status
 * @param cnn Pointer to CNN accelerator handle
 * @param status Pointer to status structure
 */
void CNN_GetStatus(CnnAccelerator_t *cnn, CnnStatus_t *status);

/**
 * Stop ongoing inference
 * @param cnn Pointer to CNN accelerator handle
 */
void CNN_Stop(CnnAccelerator_t *cnn);

/**
 * Enable/disable interrupt
 * @param cnn Pointer to CNN accelerator handle
 * @param enable 1 to enable, 0 to disable
 */
void CNN_EnableInterrupt(CnnAccelerator_t *cnn, int enable);

/**
 * Clear interrupt status
 * @param cnn Pointer to CNN accelerator handle
 */
void CNN_ClearInterrupt(CnnAccelerator_t *cnn);

/**
 * Interrupt handler (to be called from ISR)
 * @param cnn Pointer to CNN accelerator handle
 */
void CNN_InterruptHandler(CnnAccelerator_t *cnn);

/**
 * Convert Q8.8 fixed-point to float
 * @param value Q8.8 fixed-point value
 * @return Floating point equivalent
 */
float CNN_FixedToFloat(int16_t value);

/**
 * Convert float to Q8.8 fixed-point
 * @param value Floating point value
 * @return Q8.8 fixed-point equivalent
 */
int16_t CNN_FloatToFixed(float value);

/**
 * Softmax function for classification output
 * @param input Input array (fixed-point)
 * @param output Output array (floating-point probabilities)
 * @param size Array size
 */
void CNN_Softmax(const int16_t *input, float *output, int size);

/**
 * Get top-K predictions from classification output
 * @param probs Probability array
 * @param num_classes Number of classes
 * @param top_k Number of top predictions to return
 * @param results Output result array
 */
void CNN_GetTopK(const float *probs, int num_classes, int top_k, 
                 ClassificationResult_t *results);

#endif /* CNN_ACCELERATOR_H */
