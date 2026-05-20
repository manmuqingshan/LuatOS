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
    /* Reads host magic from CSR 0x13C.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int magic;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13C" : "=r"(magic));
    return magic;
}

unsigned int ndk_host_version(void) {
    /* Reads host version from CSR 0x13D.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int version;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13D" : "=r"(version));
    return version;
}

unsigned int ndk_host_features(void) {
    /* Reads host features from CSR 0x13E.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int features;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13E" : "=r"(features));
    return features;
}

unsigned int ndk_last_error(void) {
    /* Reads last error from CSR 0x13F.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int error;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13F" : "=r"(error));
    return error;
}
