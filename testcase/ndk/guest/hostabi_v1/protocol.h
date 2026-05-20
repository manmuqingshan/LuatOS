/* protocol.h - NDK Host ABI Protocol Definition */
#ifndef HOSTABI_PROTOCOL_H
#define HOSTABI_PROTOCOL_H

#include <stdint.h>
#include "../../../../components/ndk/include/luat_ndk_abi.h"

/* Command opcodes */
#define HOSTABI_CMD_QUERY_META  0x01
#define HOSTABI_CMD_DELAY_US    0x02
#define HOSTABI_CMD_EVENT_STATE 0x03

/* GPIO v2 command opcodes */
#define HOSTABI_CMD_GPIO_CONFIG     0x10
#define HOSTABI_CMD_GPIO_WRITE      0x11
#define HOSTABI_CMD_GPIO_READ       0x12
#define HOSTABI_CMD_GPIO_IRQ_STATE  0x13
#define HOSTABI_CMD_GPIO_IRQ_CLEAR  0x14

/* UART v1 command opcodes */
#define HOSTABI_CMD_UART_CONFIG    0x20
#define HOSTABI_CMD_UART_TX        0x21
#define HOSTABI_CMD_UART_RX_STATE  0x22
#define HOSTABI_CMD_UART_RX_READ   0x23
#define HOSTABI_CMD_UART_RX_CLEAR  0x24

/* UART v1 buffer offsets */
#define HOSTABI_UART_CFG_OFFSET     128u
#define HOSTABI_UART_PAYLOAD_OFFSET 256u
#define HOSTABI_UART_PORT_LOOPBACK  0x20u

/* Status codes */
#define HOSTABI_STATUS_OK           LUAT_NDK_GPIO_STATUS_OK
#define HOSTABI_STATUS_BAD_PIN      LUAT_NDK_GPIO_STATUS_BAD_PIN
#define HOSTABI_STATUS_BAD_MODE     LUAT_NDK_GPIO_STATUS_BAD_MODE
#define HOSTABI_STATUS_BAD_PULL     LUAT_NDK_GPIO_STATUS_BAD_PULL
#define HOSTABI_STATUS_BAD_IRQ_MODE LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE
#define HOSTABI_STATUS_UNSUPPORTED  LUAT_NDK_GPIO_STATUS_UNSUPPORTED
#define HOSTABI_STATUS_HOST_ERROR   LUAT_NDK_GPIO_STATUS_HOST_ERROR

/* UART v1 status codes */
#define HOSTABI_STATUS_UART_BAD_PORT   20u
#define HOSTABI_STATUS_UART_BAD_CONFIG 21u
#define HOSTABI_STATUS_UART_BAD_LENGTH 22u
#define HOSTABI_STATUS_UART_BUSY       23u
#define HOSTABI_STATUS_UART_OVERFLOW   24u

/* Command structure (16 bytes) */
typedef struct {
    uint32_t opcode;
    uint32_t arg0;
    uint32_t arg1;
    uint32_t arg2; /* GPIO_CONFIG: pull[7:0] | irq_mode[15:8] | private test flags[31:16] */
} hostabi_cmd_t;

#define HOSTABI_GPIO_CONFIG_PULL(arg2)     ((uint32_t)((arg2) & 0xFFu))
#define HOSTABI_GPIO_CONFIG_IRQ_MODE(arg2) ((uint32_t)(((arg2) >> 8) & 0xFFu))
#define HOSTABI_GPIO_TEST_FLAGS(arg2)      ((uint32_t)((arg2) & 0xFFFF0000u))
#define HOSTABI_GPIO_TEST_HOST_FAIL        (1u << 16)

/* Result structure (16 bytes) */
typedef struct {
    uint32_t status;   /* 0 = success, non-zero = error */
    uint32_t value0;
    uint32_t value1;
    uint32_t value2;
} hostabi_result_t;

/* UART v1 configuration structure (placed at HOSTABI_UART_CFG_OFFSET in the exchange buffer) */
typedef struct {
    uint32_t baud;
    uint8_t  data_bits;
    uint8_t  stop_bits;
    uint8_t  parity;
    uint8_t  rx_enable;
} hostabi_uart_cfg_t;

#endif /* HOSTABI_PROTOCOL_H */
