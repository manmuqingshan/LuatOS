#pragma once

#include <stdint.h>

#include "luat_ndk.h"

void luat_ndk_host_othercsr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value);
void luat_ndk_host_othercsr_read(luat_ndk_t *ctx, uint32_t csrno, uint32_t *value);
uint32_t luat_ndk_host_control_store(luat_ndk_t *ctx, uint32_t addy, uint32_t value);
