/*
 * CNN Accelerator Driver Implementation
 * AI Edge Accelerator for ZUBoard 1CG
 */

#include "cnn_accelerator.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "sleep.h"
#include <math.h>
#include <string.h>

/* ============================================================================
 * Private Macros
 * ============================================================================ */

#define CNN_WRITE_REG(cnn, offset, val)  Xil_Out32((cnn)->base_addr + (offset), (val))
#define CNN_READ_REG(cnn, offset)        Xil_In32((cnn)->base_addr + (offset))

/* Fixed-point conversion constants */
#define Q8_8_SCALE      256.0f
#define Q8_8_FRAC_BITS  8

/* ============================================================================
 * CNN_Init - Initialize the CNN accelerator
 * ============================================================================ */
int CNN_Init(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) {
        return XST_FAILURE;
    }
    
    /* Set default addresses */
    cnn->base_addr = CNN_ACCEL_BASE_ADDR;
    cnn->dma_video_addr = DMA_VIDEO_BASE_ADDR;
    cnn->dma_weights_addr = DMA_WEIGHTS_BASE_ADDR;
    
    /* Set default memory locations (in DDR) */
    cnn->weight_mem_addr = 0x10000000;  /* 256MB offset */
    cnn->bias_mem_addr = 0x18000000;    /* 384MB offset */
    cnn->input_frame_addr = 0x20000000; /* 512MB offset */
    cnn->output_result_addr = 0x28000000; /* 640MB offset */
    
    /* Default configuration */
    cnn->config.input_width = 128;
    cnn->config.input_height = 128;
    cnn->config.input_channels = 3;
    cnn->config.num_classes = 10;
    cnn->config.layer_enable = 0xFF;    /* All layers enabled */
    cnn->config.activation = CNN_ACT_RELU;
    cnn->config.pool_type = CNN_POOL_MAX;
    
    cnn->inference_done = 0;
    
    /* Reset the accelerator */
    CNN_Reset(cnn);
    
    /* Verify connection by reading status */
    uint32_t status = CNN_READ_REG(cnn, CNN_REG_STATUS);
    if (status == 0xFFFFFFFF) {
        /* Invalid read - hardware not accessible */
        return XST_FAILURE;
    }
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_Configure - Configure the CNN accelerator
 * ============================================================================ */
int CNN_Configure(CnnAccelerator_t *cnn, const CnnConfig_t *config)
{
    if (cnn == NULL || config == NULL) {
        return XST_FAILURE;
    }
    
    /* Check for valid configuration */
    if (config->input_width == 0 || config->input_height == 0 ||
        config->input_width > 224 || config->input_height > 224) {
        return XST_FAILURE;
    }
    
    /* Copy configuration */
    memcpy(&cnn->config, config, sizeof(CnnConfig_t));
    
    /* Build config register value */
    uint32_t cfg_reg = 0;
    cfg_reg |= (config->layer_enable & CNN_CFG_LAYER_EN_MASK);
    cfg_reg |= ((config->activation << CNN_CFG_ACT_SHIFT) & CNN_CFG_ACT_MASK);
    if (config->pool_type == CNN_POOL_AVG) {
        cfg_reg |= CNN_CFG_POOL_TYPE;
    }
    
    /* Write configuration registers */
    CNN_WRITE_REG(cnn, CNN_REG_CONFIG, cfg_reg);
    
    /* Set input dimensions */
    uint32_t dim_reg = (config->input_height << 16) | config->input_width;
    CNN_WRITE_REG(cnn, CNN_REG_INPUT_DIM, dim_reg);
    
    /* Set memory addresses */
    CNN_WRITE_REG(cnn, CNN_REG_WEIGHT_ADDR, cnn->weight_mem_addr);
    CNN_WRITE_REG(cnn, CNN_REG_BIAS_ADDR, cnn->bias_mem_addr);
    CNN_WRITE_REG(cnn, CNN_REG_INPUT_ADDR, cnn->input_frame_addr);
    CNN_WRITE_REG(cnn, CNN_REG_OUTPUT_ADDR, cnn->output_result_addr);
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_Reset - Reset the CNN accelerator
 * ============================================================================ */
void CNN_Reset(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) return;
    
    /* Assert reset */
    CNN_WRITE_REG(cnn, CNN_REG_CONTROL, CNN_CTRL_RESET);
    
    /* Brief delay for reset to take effect */
    usleep(10);
    
    /* Clear reset */
    CNN_WRITE_REG(cnn, CNN_REG_CONTROL, 0);
    
    /* Clear interrupt status */
    CNN_WRITE_REG(cnn, CNN_REG_IRQ_STATUS, 0xFFFFFFFF);
    
    cnn->inference_done = 0;
}

/* ============================================================================
 * CNN_LoadWeights - Load weights from memory
 * ============================================================================ */
int CNN_LoadWeights(CnnAccelerator_t *cnn, const int16_t *weights, uint32_t size)
{
    if (cnn == NULL || weights == NULL || size == 0) {
        return XST_FAILURE;
    }
    
    /* Copy weights to designated memory region */
    memcpy((void *)cnn->weight_mem_addr, weights, size);
    
    /* Flush cache to ensure data is in DDR */
    Xil_DCacheFlushRange(cnn->weight_mem_addr, size);
    
    /* Update weight address register */
    CNN_WRITE_REG(cnn, CNN_REG_WEIGHT_ADDR, cnn->weight_mem_addr);
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_LoadBiases - Load biases from memory
 * ============================================================================ */
int CNN_LoadBiases(CnnAccelerator_t *cnn, const int16_t *biases, uint32_t size)
{
    if (cnn == NULL || biases == NULL || size == 0) {
        return XST_FAILURE;
    }
    
    /* Copy biases to designated memory region */
    memcpy((void *)cnn->bias_mem_addr, biases, size);
    
    /* Flush cache */
    Xil_DCacheFlushRange(cnn->bias_mem_addr, size);
    
    /* Update bias address register */
    CNN_WRITE_REG(cnn, CNN_REG_BIAS_ADDR, cnn->bias_mem_addr);
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_StartInference - Start inference (non-blocking)
 * ============================================================================ */
int CNN_StartInference(CnnAccelerator_t *cnn, uint32_t frame_addr)
{
    if (cnn == NULL) {
        return XST_FAILURE;
    }
    
    /* Check if accelerator is busy */
    uint32_t status = CNN_READ_REG(cnn, CNN_REG_STATUS);
    if (status & CNN_STAT_BUSY) {
        return XST_FAILURE;
    }
    
    /* Update input frame address */
    CNN_WRITE_REG(cnn, CNN_REG_INPUT_ADDR, frame_addr);
    
    /* Flush input frame cache */
    uint32_t frame_size = cnn->config.input_width * cnn->config.input_height * 
                          cnn->config.input_channels * sizeof(int16_t);
    Xil_DCacheFlushRange(frame_addr, frame_size);
    
    /* Clear done flag */
    cnn->inference_done = 0;
    
    /* Start inference */
    CNN_WRITE_REG(cnn, CNN_REG_CONTROL, CNN_CTRL_START);
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_WaitForCompletion - Wait for inference to complete
 * ============================================================================ */
int CNN_WaitForCompletion(CnnAccelerator_t *cnn, uint32_t timeout_ms)
{
    if (cnn == NULL) {
        return XST_FAILURE;
    }
    
    uint32_t elapsed = 0;
    uint32_t poll_interval = 1; /* 1ms */
    
    while (1) {
        uint32_t status = CNN_READ_REG(cnn, CNN_REG_STATUS);
        
        if (status & CNN_STAT_DONE) {
            cnn->inference_done = 1;
            return XST_SUCCESS;
        }
        
        if (!(status & CNN_STAT_BUSY)) {
            /* Not busy but not done - check for error */
            if (status & CNN_STAT_ERROR_MASK) {
                return XST_FAILURE;
            }
            /* May have completed between checks */
            if (CNN_READ_REG(cnn, CNN_REG_STATUS) & CNN_STAT_DONE) {
                cnn->inference_done = 1;
                return XST_SUCCESS;
            }
        }
        
        /* Check timeout */
        if (timeout_ms > 0 && elapsed >= timeout_ms) {
            return XST_FAILURE;
        }
        
        usleep(poll_interval * 1000);
        elapsed += poll_interval;
    }
}

/* ============================================================================
 * CNN_IsComplete - Check if inference is complete (non-blocking)
 * ============================================================================ */
int CNN_IsComplete(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) return 0;
    
    if (cnn->inference_done) return 1;
    
    uint32_t status = CNN_READ_REG(cnn, CNN_REG_STATUS);
    if (status & CNN_STAT_DONE) {
        cnn->inference_done = 1;
        return 1;
    }
    
    return 0;
}

/* ============================================================================
 * CNN_GetResult - Get inference results
 * ============================================================================ */
int CNN_GetResult(CnnAccelerator_t *cnn, InferenceResult_t *result)
{
    if (cnn == NULL || result == NULL) {
        return XST_FAILURE;
    }
    
    if (!cnn->inference_done) {
        return XST_FAILURE;
    }
    
    /* Invalidate cache for output region */
    uint32_t output_size = cnn->config.num_classes * sizeof(int16_t);
    Xil_DCacheInvalidateRange(cnn->output_result_addr, output_size);
    
    /* Read raw output (fixed-point) */
    int16_t *raw_output = (int16_t *)cnn->output_result_addr;
    
    /* Convert to floating point probabilities */
    float probs[CNN_MAX_CLASSES];
    CNN_Softmax(raw_output, probs, cnn->config.num_classes);
    
    /* Get top predictions */
    result->num_results = (cnn->config.num_classes < 5) ? cnn->config.num_classes : 5;
    CNN_GetTopK(probs, cnn->config.num_classes, result->num_results, 
                result->classifications);
    
    return XST_SUCCESS;
}

/* ============================================================================
 * CNN_GetStatus - Get accelerator status
 * ============================================================================ */
void CNN_GetStatus(CnnAccelerator_t *cnn, CnnStatus_t *status)
{
    if (cnn == NULL || status == NULL) return;
    
    uint32_t reg_status = CNN_READ_REG(cnn, CNN_REG_STATUS);
    
    status->busy = (reg_status & CNN_STAT_BUSY) ? 1 : 0;
    status->done = (reg_status & CNN_STAT_DONE) ? 1 : 0;
    status->error_code = (reg_status & CNN_STAT_ERROR_MASK) >> 4;
    status->cycles = CNN_READ_REG(cnn, CNN_REG_PERF_CYCLES);
    status->operations = CNN_READ_REG(cnn, CNN_REG_PERF_OPS);
}

/* ============================================================================
 * CNN_Stop - Stop ongoing inference
 * ============================================================================ */
void CNN_Stop(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) return;
    
    CNN_WRITE_REG(cnn, CNN_REG_CONTROL, CNN_CTRL_STOP);
    cnn->inference_done = 0;
}

/* ============================================================================
 * CNN_EnableInterrupt - Enable/disable interrupt
 * ============================================================================ */
void CNN_EnableInterrupt(CnnAccelerator_t *cnn, int enable)
{
    if (cnn == NULL) return;
    
    if (enable) {
        CNN_WRITE_REG(cnn, CNN_REG_IRQ_ENABLE, CNN_IRQ_DONE | CNN_IRQ_ERROR);
    } else {
        CNN_WRITE_REG(cnn, CNN_REG_IRQ_ENABLE, 0);
    }
}

/* ============================================================================
 * CNN_ClearInterrupt - Clear interrupt status
 * ============================================================================ */
void CNN_ClearInterrupt(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) return;
    
    /* Write 1 to clear */
    uint32_t irq_status = CNN_READ_REG(cnn, CNN_REG_IRQ_STATUS);
    CNN_WRITE_REG(cnn, CNN_REG_IRQ_STATUS, irq_status);
}

/* ============================================================================
 * CNN_InterruptHandler - Interrupt handler
 * ============================================================================ */
void CNN_InterruptHandler(CnnAccelerator_t *cnn)
{
    if (cnn == NULL) return;
    
    uint32_t irq_status = CNN_READ_REG(cnn, CNN_REG_IRQ_STATUS);
    
    if (irq_status & CNN_IRQ_DONE) {
        cnn->inference_done = 1;
    }
    
    /* Clear handled interrupts */
    CNN_WRITE_REG(cnn, CNN_REG_IRQ_STATUS, irq_status);
}

/* ============================================================================
 * CNN_FixedToFloat - Convert Q8.8 to float
 * ============================================================================ */
float CNN_FixedToFloat(int16_t value)
{
    return (float)value / Q8_8_SCALE;
}

/* ============================================================================
 * CNN_FloatToFixed - Convert float to Q8.8
 * ============================================================================ */
int16_t CNN_FloatToFixed(float value)
{
    float scaled = value * Q8_8_SCALE;
    
    /* Clamp to int16 range */
    if (scaled > 32767.0f) scaled = 32767.0f;
    if (scaled < -32768.0f) scaled = -32768.0f;
    
    return (int16_t)scaled;
}

/* ============================================================================
 * CNN_Softmax - Apply softmax to output
 * ============================================================================ */
void CNN_Softmax(const int16_t *input, float *output, int size)
{
    float max_val = CNN_FixedToFloat(input[0]);
    float sum = 0.0f;
    
    /* Find max for numerical stability */
    for (int i = 1; i < size; i++) {
        float val = CNN_FixedToFloat(input[i]);
        if (val > max_val) max_val = val;
    }
    
    /* Compute exp and sum */
    for (int i = 0; i < size; i++) {
        float val = CNN_FixedToFloat(input[i]);
        output[i] = expf(val - max_val);
        sum += output[i];
    }
    
    /* Normalize */
    for (int i = 0; i < size; i++) {
        output[i] /= sum;
    }
}

/* ============================================================================
 * CNN_GetTopK - Get top K predictions
 * ============================================================================ */
void CNN_GetTopK(const float *probs, int num_classes, int top_k, 
                 ClassificationResult_t *results)
{
    /* Simple selection algorithm for small K */
    uint8_t selected[CNN_MAX_CLASSES] = {0};
    
    for (int k = 0; k < top_k; k++) {
        float max_prob = -1.0f;
        int max_idx = -1;
        
        for (int i = 0; i < num_classes; i++) {
            if (!selected[i] && probs[i] > max_prob) {
                max_prob = probs[i];
                max_idx = i;
            }
        }
        
        if (max_idx >= 0) {
            results[k].class_id = max_idx;
            results[k].confidence = max_prob;
            selected[max_idx] = 1;
        }
    }
}
