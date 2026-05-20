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
