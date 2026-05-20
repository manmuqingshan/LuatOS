#include "luat_ndk_host.h"

#include "luat_gpio.h"
#include "luat_ndk_abi.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "mini-rv32ima.h"

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

#define NDK_MAX_LOG_STR 120
#define NDK_CSR_PRINT_NUM 0x136
#define NDK_CSR_PRINT_PTR 0x137
#define NDK_CSR_PRINT_STR 0x138
#define NDK_CSR_EXCHANGE_BASE 0x139
#define NDK_CSR_EXCHANGE_SIZE 0x13A
#define NDK_CSR_MEMORY_SIZE 0x13B
#define NDK_CSR_GPIO_SET 0x200
#define NDK_CSR_GPIO_GET 0x201

static inline bool ndk_addr_valid(luat_ndk_t *ctx, uint32_t addr, size_t len) {
    if (!ctx) return false;
    if (addr < MINIRV32_RAM_IMAGE_OFFSET) return false;
    uint64_t start = (uint64_t)(addr - MINIRV32_RAM_IMAGE_OFFSET);
    uint64_t end = start + len;
    return end <= ctx->ram_size;
}

static void ndk_log_string(luat_ndk_t *ctx, uint32_t guest_addr) {
    if (!ctx) return;
    if (!ndk_addr_valid(ctx, guest_addr, 1)) return;
    uint32_t off = guest_addr - MINIRV32_RAM_IMAGE_OFFSET;
    char tmp[NDK_MAX_LOG_STR + 1];
    size_t i = 0;
    for (; i < NDK_MAX_LOG_STR && off + i < ctx->ram_size; i++) {
        tmp[i] = (char)ctx->ram[off + i];
        if (tmp[i] == '\0') break;
    }
    tmp[i] = '\0';
    LLOGI("vm: %s", tmp);
}

void luat_ndk_host_othercsr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value) {
    if (!ctx) return;
    switch (csrno) {
    case NDK_CSR_PRINT_NUM:
        LLOGI("vm num: %u", value);
        break;
    case NDK_CSR_PRINT_PTR:
        LLOGI("vm ptr: 0x%08X", value);
        break;
    case NDK_CSR_PRINT_STR:
        ndk_log_string(ctx, value);
        break;
    case NDK_CSR_GPIO_SET: {
        uint32_t pin = value & 0xFFFF;
        uint32_t level = (value >> 16) & 0x1;
        luat_gpio_set(pin, level);
        break;
    }
    case NDK_CSR_DELAY_US: {
        // Validate delay value (max 1 second)
        if (value > 1000000) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            break;
        }
        // Sleep for requested duration (convert us to ms, rounding up)
        uint32_t ms = (value + 999) / 1000;
        if (ms > 0) {
            luat_rtos_task_sleep(ms);
        }
        // Push timer event if enabled
        if (ctx->event_enabled) {
            luat_ndk_event_push_timer(ctx, value);
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        break;
    }
    case NDK_CSR_EVENT_ENABLE:
        ctx->event_enabled = (value ? 1 : 0);
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        break;
    default:
        break;
    }
}

void luat_ndk_host_othercsr_read(luat_ndk_t *ctx, uint32_t csrno, uint32_t *value) {
    if (!ctx || !value) return;
    uint32_t tmp = 0;
    switch (csrno) {
    case NDK_CSR_EXCHANGE_BASE:
        *value = MINIRV32_RAM_IMAGE_OFFSET + ctx->exchange_offset;
        break;
    case NDK_CSR_EXCHANGE_SIZE:
        *value = (uint32_t)ctx->exchange_size;
        break;
    case NDK_CSR_MEMORY_SIZE:
        *value = (uint32_t)ctx->ram_size;
        break;
    case NDK_CSR_HOST_MAGIC:
        *value = LUAT_NDK_HOST_MAGIC;
        break;
    case NDK_CSR_HOST_VERSION:
        *value = LUAT_NDK_HOST_VERSION;
        break;
    case NDK_CSR_HOST_FEATURES:
        *value = ctx->abi_features;
        break;
    case NDK_CSR_HOST_LAST_ERROR:
        *value = ctx->last_error;
        break;
    case NDK_CSR_EVENT_SLOTS:
        *value = ctx->event_slots;
        break;
    case NDK_CSR_GPIO_GET:
        tmp = (*value) & 0xFFFF;
        *value = (uint32_t)luat_gpio_get(tmp);
        break;
    case NDK_CSR_TIME_US_LO: {
        // Use millisecond-based timer converted to microseconds
        uint64_t us = luat_mcu_tick64_ms() * 1000ull;
        *value = (uint32_t)(us & 0xFFFFFFFFull);
        break;
    }
    case NDK_CSR_TIME_US_HI: {
        uint64_t us = luat_mcu_tick64_ms() * 1000ull;
        *value = (uint32_t)(us >> 32);
        break;
    }
    case NDK_CSR_EVENT_PENDING: {
        // Check if host_write != guest_read
        luat_ndk_event_header_t *hdr = (luat_ndk_event_header_t*)(ctx->ram + ctx->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET);
        *value = (hdr->host_write != hdr->guest_read) ? 1 : 0;
        break;
    }
    default:
        *value = 0;
        break;
    }
}

uint32_t luat_ndk_host_control_store(luat_ndk_t *ctx, uint32_t addy, uint32_t value) {
    if (addy == 0x11100000) {
        LLOGD("Control Store: set val to %08X", value);
        ctx->core->pc = ctx->core->pc + 4;
        return value;
    }
    LLOGD("Control Store: unknown addy %08X val %08X", addy, value);
    return 0;
}
