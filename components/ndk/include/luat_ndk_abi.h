#pragma once

#include <stdint.h>

// Host ABI Magic and Version
#define LUAT_NDK_HOST_MAGIC   0x4E444B31u  // "NDK1"
#define LUAT_NDK_HOST_VERSION 0x00010000u  // 1.0.0

// Discovery CSR addresses
#define NDK_CSR_HOST_MAGIC      0x13C
#define NDK_CSR_HOST_VERSION    0x13D
#define NDK_CSR_HOST_FEATURES   0x13E
#define NDK_CSR_HOST_LAST_ERROR 0x13F
#define NDK_CSR_EVENT_SLOTS     0x140

// Time and delay CSR addresses
#define NDK_CSR_TIME_US_LO      0x141
#define NDK_CSR_TIME_US_HI      0x142
#define NDK_CSR_DELAY_US        0x143

// Event CSR addresses
#define NDK_CSR_EVENT_ENABLE    0x144
#define NDK_CSR_EVENT_PENDING   0x145

// Feature flags
#define LUAT_NDK_FEATURE_META   (1u << 0)
#define LUAT_NDK_FEATURE_TIME   (1u << 1)
#define LUAT_NDK_FEATURE_EVENT  (1u << 2)

// Host error codes
typedef enum {
    LUAT_NDK_HOST_ERR_NONE = 0,
    LUAT_NDK_HOST_ERR_BAD_OPCODE = 1,
    LUAT_NDK_HOST_ERR_PARAM = 2,
    LUAT_NDK_HOST_ERR_UNSUPPORTED = 3
} luat_ndk_host_err_t;

// Exchange buffer layout
#define LUAT_NDK_COMMAND_OFFSET  0
#define LUAT_NDK_COMMAND_SIZE    16
#define LUAT_NDK_RESULT_OFFSET   16
#define LUAT_NDK_RESULT_SIZE     16
#define LUAT_NDK_EVENT_HDR_OFFSET 32
#define LUAT_NDK_EVENT_HDR_SIZE  16

// Event types
#define LUAT_NDK_EVENT_NONE     0u
#define LUAT_NDK_EVENT_TIMER    1u

// Event header structure (16 bytes)
typedef struct {
    uint32_t host_write;   // Number of events written by host
    uint32_t guest_read;   // Number of events read by guest
    uint32_t slot_count;   // Total number of event slots available
    uint32_t overflow;     // Set to 1 if event was dropped due to full ring
} luat_ndk_event_header_t;

// Event structure (8 bytes)
typedef struct {
    uint16_t type;         // Event type (LUAT_NDK_EVENT_*)
    uint16_t source;       // Event source identifier
    uint32_t data;         // Event-specific data
} luat_ndk_event_t;
