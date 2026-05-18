#include "luat_base.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"
#include "luat_log.h"

#define LUAT_LOG_TAG "uart.web"
#include "luat_log.h"

static int uart_setup_web(void *userdata, luat_uart_t *uart) {
    (void)userdata;
    if (uart == NULL) {
        return -1;
    }
    LLOGW("uart[%d] web build uses no-op stub", uart->id);
    return 0;
}

static int uart_write_web(void *userdata, int uart_id, void *data, size_t length) {
    (void)userdata;
    (void)uart_id;
    (void)data;
    return (int)length;
}

static int uart_read_web(void *userdata, int uart_id, void *buffer, size_t length) {
    (void)userdata;
    (void)uart_id;
    (void)buffer;
    (void)length;
    return 0;
}

static int uart_close_web(void *userdata, int uart_id) {
    (void)userdata;
    (void)uart_id;
    return 0;
}

const luat_uart_drv_opts_t uart_web = {
    .setup = uart_setup_web,
    .write = uart_write_web,
    .read = uart_read_web,
    .close = uart_close_web,
};
