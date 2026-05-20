/* protocol.h - NDK Host ABI Protocol Definition */
#ifndef HOSTABI_PROTOCOL_H
#define HOSTABI_PROTOCOL_H

#include <stdint.h>

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

/* Status codes */
#define HOSTABI_STATUS_OK           0u
#define HOSTABI_STATUS_BAD_PIN      10u
#define HOSTABI_STATUS_BAD_MODE     11u
#define HOSTABI_STATUS_BAD_PULL     12u
#define HOSTABI_STATUS_BAD_IRQ_MODE 13u
#define HOSTABI_STATUS_UNSUPPORTED  14u

/* Command structure (16 bytes) */
typedef struct {
    uint32_t opcode;
    uint32_t arg0;
    uint32_t arg1;
    uint32_t arg2;
} hostabi_cmd_t;

/* Result structure (16 bytes) */
typedef struct {
    uint32_t status;   /* 0 = success, non-zero = error */
    uint32_t value0;
    uint32_t value1;
    uint32_t value2;
} hostabi_result_t;

#endif /* HOSTABI_PROTOCOL_H */
