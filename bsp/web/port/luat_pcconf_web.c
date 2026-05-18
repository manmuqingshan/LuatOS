#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_uart_drv.h"
#include "luat_pcconf.h"

#define LUAT_LOG_TAG "pc.web"
#include "luat_log.h"

extern const luat_uart_drv_opts_t uart_web;
extern const luat_uart_drv_opts_t *uart_drvs[];

luat_pcconf_t g_pcconf;

void luat_pcconf_init(void) {
    for (size_t i = 0; i < 128; i++) {
        uart_drvs[i] = &uart_web;
    }
    LLOGI("browser pcconf initialized");
}

void luat_pcconf_save(void) {
}
