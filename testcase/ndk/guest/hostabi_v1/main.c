/* main.c - NDK Host ABI Test Fixture */
#include "protocol.h"

/* NDK builtin APIs from luat_ndk_builtin.h */
extern unsigned int ndk_exchange_base(void);
extern unsigned int ndk_memory_size(void);
extern void ndk_delay_us(unsigned int us);
extern unsigned int ndk_time_us_lo(void);
extern void ndk_event_enable(unsigned int enabled);
extern unsigned int ndk_event_pending(void);

/* NDK builtin host API (implemented in ndk_stubs.c) */
unsigned int ndk_host_magic(void);
unsigned int ndk_host_version(void);
unsigned int ndk_host_features(void);
unsigned int ndk_last_error(void);

/* Forward declaration of main */
int main(void);

/* Memory-mapped control register */
#define CONTROL_STORE (*(volatile unsigned int*)0x11100000)

/* Command and result are in the exchange buffer at offset 0 and 16 bytes respectively */
static volatile hostabi_cmd_t* cmd_buf(void) {
    return (volatile hostabi_cmd_t*)ndk_exchange_base();
}

static volatile hostabi_result_t* result_buf(void) {
    return (volatile hostabi_result_t*)(ndk_exchange_base() + sizeof(hostabi_cmd_t));
}

/* _start - Entry point that initializes stack pointer before calling main */
__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile(
        ".option norvc\n"
        /* Read memory size from CSR 0x13B */
        "csrr a0, 0x13B\n"
        /* Compute stack top: 0x80000000 + mem_size - 16 */
        "lui a1, 0x80000\n"
        "add a0, a0, a1\n"
        "addi a0, a0, -16\n"
        /* Initialize stack pointer */
        "mv sp, a0\n"
        /* Call main */
        "call main\n"
        /* Infinite loop if main returns */
        "1: wfi\n"
        "j 1b\n"
        : /* no outputs */
        : /* no inputs */
        : "a0", "a1"
    );
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
    } else if (cmd->opcode == HOSTABI_CMD_DELAY_US) {
        /* Enable events before delay */
        ndk_event_enable(1);
        /* Request delay */
        ndk_delay_us(cmd->arg0);
        /* Return timestamp and pending flag */
        out->value0 = ndk_time_us_lo();
        out->value1 = ndk_event_pending();
    } else if (cmd->opcode == HOSTABI_CMD_EVENT_STATE) {
        /* Query event state */
        out->value0 = ndk_event_pending();
    } else {
        out->status = 1;
        out->value0 = ndk_last_error();
    }

    /* Signal completion */
    CONTROL_STORE = 0x5555;
    return 0;
}
