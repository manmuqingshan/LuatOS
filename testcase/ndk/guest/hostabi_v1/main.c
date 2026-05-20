/* main.c - NDK Host ABI Test Fixture */
#include "protocol.h"

/* NDK builtin APIs from luat_ndk_builtin.h */
extern unsigned int ndk_exchange_base(void);

/* NDK builtin host API (implemented in ndk_stubs.c) */
unsigned int ndk_host_magic(void);
unsigned int ndk_host_version(void);
unsigned int ndk_host_features(void);
unsigned int ndk_last_error(void);

/* Memory-mapped control register */
#define CONTROL_STORE (*(volatile unsigned int*)0x11100000)

/* Command and result are in the exchange buffer at offset 0 and 16 bytes respectively */
static volatile hostabi_cmd_t* cmd_buf(void) {
    return (volatile hostabi_cmd_t*)ndk_exchange_base();
}

static volatile hostabi_result_t* result_buf(void) {
    return (volatile hostabi_result_t*)(ndk_exchange_base() + sizeof(hostabi_cmd_t));
}

int main(void) {
    volatile hostabi_cmd_t* cmd = cmd_buf();
    volatile hostabi_result_t* out = result_buf();
    
    /* Initialize result to success */
    out->status = 0;
    out->value0 = 0;
    out->value1 = 0;
    out->value2 = 0;

    /* Process command */
    if (cmd->opcode == HOSTABI_CMD_QUERY_META) {
        out->value0 = ndk_host_magic();
        out->value1 = ndk_host_version();
        out->value2 = ndk_host_features();
    } else {
        out->status = 1;
        out->value0 = ndk_last_error();
    }

    /* Signal completion */
    CONTROL_STORE = 0x5555;
    return 0;
}
