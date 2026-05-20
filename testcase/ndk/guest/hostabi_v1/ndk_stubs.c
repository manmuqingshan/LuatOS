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

void ndk_delay_us(unsigned int us) {
    /* Writes delay request to CSR 0x143 (NDK_CSR_DELAY_US).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    __asm__ volatile(".option norvc\ncsrrw x0, 0x143, %0" :: "r"(us));
}

unsigned int ndk_time_us_lo(void) {
    /* Reads low 32 bits of microsecond timestamp from CSR 0x141 (NDK_CSR_TIME_US_LO).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int time_lo;
    __asm__ volatile(".option norvc\ncsrr %0, 0x141" : "=r"(time_lo));
    return time_lo;
}

void ndk_event_enable(unsigned int enabled) {
    /* Writes event enable flag to CSR 0x144 (NDK_CSR_EVENT_ENABLE).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    __asm__ volatile(".option norvc\ncsrrw x0, 0x144, %0" :: "r"(enabled));
}

unsigned int ndk_event_pending(void) {
    /* Reads event pending flag from CSR 0x145 (NDK_CSR_EVENT_PENDING).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int pending;
    __asm__ volatile(".option norvc\ncsrr %0, 0x145" : "=r"(pending));
    return pending;
}
