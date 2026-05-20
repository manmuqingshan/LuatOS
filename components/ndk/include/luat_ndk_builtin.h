#pragma once

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "luat_ndk_abi.h"

// CSR numbers used for host interaction
#define NDK_CSR_PRINT_NUM 0x136
#define NDK_CSR_PRINT_PTR 0x137
#define NDK_CSR_PRINT_STR 0x138
#define NDK_CSR_EXCHANGE_BASE 0x139
#define NDK_CSR_EXCHANGE_SIZE 0x13A
#define NDK_CSR_MEMORY_SIZE  0x13B
#define NDK_CSR_GPIO_SET     0x200
#define NDK_CSR_GPIO_GET     0x201

static inline uint32_t ndk_exchange_base(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EXCHANGE_BASE));
    return v;
}

static inline uint32_t ndk_exchange_size(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EXCHANGE_SIZE));
    return v;
}

static inline uint32_t ndk_memory_size(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_MEMORY_SIZE));
    return v;
}

static inline void ndk_lprint(const char *s) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_STR), "r"(s));
}

static inline void ndk_pprint(uint32_t ptr) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_PTR), "r"(ptr));
}

static inline void ndk_nprint(uint32_t value) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_NUM), "r"(value));
}

// Write GPIO level: value = (level << 16) | pin
static inline void ndk_gpio_set(uint32_t pin, uint32_t level) {
    uint32_t v = (level << 16) | (pin & 0xFFFF);
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_GPIO_SET), "r"(v));
}

// Read GPIO level: write pin via csrrw, then read result
static inline uint32_t ndk_gpio_get(uint32_t pin) {
    uint32_t v = pin & 0xFFFF;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_GPIO_GET));
    return v;
}

static inline uint32_t ndk_host_magic(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_HOST_MAGIC));
    return v;
}

static inline uint32_t ndk_host_version(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_HOST_VERSION));
    return v;
}

static inline uint32_t ndk_host_features(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_HOST_FEATURES));
    return v;
}

static inline uint32_t ndk_last_error(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_HOST_LAST_ERROR));
    return v;
}

static inline uint32_t ndk_host_last_error(void) {
    return ndk_last_error();
}

/* GPIO v2 uses csrrw a0, csr, a0 on purpose: the host resolves these CSRs
 * from the CSR read path and inspects the guest's current a0 payload. */
static inline uint32_t ndk_gpio_config(uint32_t pin, uint32_t mode, uint32_t pull, uint32_t irq_mode) {
    register uint32_t a0 __asm__("a0") =
        ((irq_mode & 0xFFu) << 24) | ((pull & 0xFFu) << 16) | ((mode & 0xFFu) << 8) | (pin & 0xFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_GPIO_CONFIG));
    return a0;
}

static inline uint32_t ndk_gpio_write_v2(uint32_t pin, uint32_t level) {
    register uint32_t a0 __asm__("a0") = ((level & 0x1u) << 16) | (pin & 0xFFFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_GPIO_WRITE_V2));
    return a0;
}

static inline uint32_t ndk_gpio_read_v2(uint32_t pin) {
    register uint32_t a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_GPIO_READ_V2));
    return a0;
}

static inline uint32_t ndk_gpio_irq_state(uint32_t pin) {
    register uint32_t a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_GPIO_IRQ_STATE));
    return a0;
}

static inline uint32_t ndk_gpio_irq_clear(uint32_t pin) {
    register uint32_t a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_GPIO_IRQ_CLEAR));
    return a0;
}

// Time and delay APIs (microsecond precision, may use millisecond-based implementation)
static inline uint32_t ndk_time_us_lo(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_TIME_US_LO));
    return v;
}

static inline uint32_t ndk_time_us_hi(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_TIME_US_HI));
    return v;
}

static inline void ndk_delay_us(uint32_t us) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_DELAY_US), "r"(us));
}

// Event APIs
static inline void ndk_event_enable(uint32_t enabled) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_EVENT_ENABLE), "r"(enabled));
}

static inline uint32_t ndk_event_pending(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EVENT_PENDING));
    return v;
}

// Provide a familiar alias for the shared buffer base
#define USERDATA (ndk_exchange_base())

// UART v1 guest CSR wrappers
static inline uint32_t ndk_uart_config(uint32_t port, uint32_t cfg_offset) {
    register uint32_t a0 __asm__("a0") = LUAT_NDK_UART_PTR_PACK(port, cfg_offset);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_UART_CONFIG));
    return a0;
}

static inline uint32_t ndk_uart_tx(uint32_t port, uint32_t data_offset, uint32_t length) {
    register uint32_t a0 __asm__("a0") = LUAT_NDK_UART_IO_PACK(port, data_offset, length);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_UART_TX));
    return a0;
}

static inline uint32_t ndk_uart_rx_state(uint32_t port) {
    register uint32_t a0 __asm__("a0") = port & 0xFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_UART_RX_STATE));
    return a0;
}

static inline uint32_t ndk_uart_rx_read(uint32_t port, uint32_t data_offset, uint32_t length) {
    register uint32_t a0 __asm__("a0") = LUAT_NDK_UART_IO_PACK(port, data_offset, length);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_UART_RX_READ));
    return a0;
}

static inline uint32_t ndk_uart_rx_clear(uint32_t port) {
    register uint32_t a0 __asm__("a0") = port & 0xFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_UART_RX_CLEAR));
    return a0;
}
