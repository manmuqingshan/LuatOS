/* ndk_stubs.c - Stub implementations for NDK host API functions */

/* These are placeholder implementations until the actual host ABI is implemented */

unsigned int ndk_exchange_base(void) {
    /* This stub returns the exchange base address.
     * In a real implementation, this would read from CSR 0x139.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int base;
    __asm__ volatile(".option norvc\ncsrr %0, 0x139" : "=r"(base));
    return base;
}

unsigned int ndk_memory_size(void) {
    /* Returns the guest memory size in bytes by reading CSR 0x13B.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int size;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

unsigned int ndk_host_magic(void) {
    return 0x4E444B31;  /* "NDK1" */
}

unsigned int ndk_host_version(void) {
    return 0x00010000;  /* 1.0.0 */
}

unsigned int ndk_host_features(void) {
    return 0x00000000;  /* No features yet */
}

unsigned int ndk_last_error(void) {
    return 0;  /* No error */
}
