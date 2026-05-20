/* protocol.h - NDK Host ABI Protocol Definition */
#ifndef HOSTABI_PROTOCOL_H
#define HOSTABI_PROTOCOL_H

#include <stdint.h>

/* Command opcodes */
#define HOSTABI_CMD_QUERY_META  0x01
#define HOSTABI_CMD_DELAY_US    0x02
#define HOSTABI_CMD_EVENT_STATE 0x03

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
