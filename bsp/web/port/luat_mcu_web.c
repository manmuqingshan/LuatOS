#include "luat_base.h"
#include "luat_mcu.h"

#include "luat_posix_compat.h"

#define LUAT_LOG_TAG "mcu.web"
#include "luat_log.h"

#include <string.h>

static int g_clk_mhz = 24;
static char g_unique_id[32] = "WEB000000000000";
static uint64_t g_startup_ns = 0;

int luat_mcu_set_clk(size_t mhz) {
    g_clk_mhz = (int)mhz;
    return 0;
}

int luat_mcu_get_clk(void) {
    return g_clk_mhz;
}

const char *luat_mcu_unique_id(size_t *t) {
    if (t) {
        *t = strlen(g_unique_id);
    }
    return g_unique_id;
}

long luat_mcu_ticks(void) {
    return (long)(luat_mcu_tick64() / 1000);
}

uint32_t luat_mcu_hz(void) {
    return 1;
}

uint64_t luat_mcu_tick64(void) {
    if (g_startup_ns == 0) {
        g_startup_ns = luat_monotonic_ns();
    }
    return (luat_monotonic_ns() - g_startup_ns) / 1000ULL;
}

int luat_mcu_us_period(void) {
    return 1;
}

uint64_t luat_mcu_tick64_ms(void) {
    return luat_mcu_tick64() / 1000ULL;
}

void luat_mcu_set_clk_source(uint8_t source_main, uint8_t source_32k, uint32_t delay) {
    (void)source_main;
    (void)source_32k;
    (void)delay;
}

void luat_mcu_iomux_ctrl(uint8_t type, uint8_t sn, int pad_index, uint8_t alt, uint8_t is_input) {
    (void)type;
    (void)sn;
    (void)pad_index;
    (void)alt;
    (void)is_input;
}

void luat_mcu_set_hardfault_mode(int mode) {
    (void)mode;
}

void luat_mcu_xtal_ref_output(uint8_t main_enable, uint8_t slow_32k_enable) {
    (void)main_enable;
    (void)slow_32k_enable;
}

int luat_mcu_muid(char *buf) {
    if (buf == NULL) {
        return -1;
    }
    memcpy(buf, g_unique_id, strlen(g_unique_id) + 1);
    return 0;
}

void luat_mcu_startup_init(void) {
    g_startup_ns = luat_monotonic_ns();
}
