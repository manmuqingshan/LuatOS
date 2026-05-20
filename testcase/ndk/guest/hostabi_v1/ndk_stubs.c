/* ndk_stubs.c - Stub implementations for NDK host API functions */

/* These are placeholder implementations until the actual host ABI is implemented */

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
