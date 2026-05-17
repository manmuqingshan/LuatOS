#include "luat_base.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"
#include "luat_log.h"

const luat_uart_drv_opts_t *uart_drvs[128] = {0};

int luat_uart_setup(luat_uart_t *uart) {
    if (uart == NULL || uart->id >= 128) {
        return -1;
    }
    const luat_uart_drv_opts_t *drv = uart_drvs[uart->id];
    if (drv == NULL || drv->setup == NULL) {
        return -1;
    }
    return drv->setup(NULL, uart);
}

int luat_uart_write(int uart_id, void *data, size_t length) {
    if (uart_id < 0 || uart_id >= 128) {
        return -1;
    }
    const luat_uart_drv_opts_t *drv = uart_drvs[uart_id];
    if (drv == NULL || drv->write == NULL) {
        return -1;
    }
    return drv->write(NULL, uart_id, data, length);
}

int luat_uart_read(int uart_id, void *buffer, size_t length) {
    if (uart_id < 0 || uart_id >= 128) {
        return -1;
    }
    const luat_uart_drv_opts_t *drv = uart_drvs[uart_id];
    if (drv == NULL || drv->read == NULL) {
        return -1;
    }
    return drv->read(NULL, uart_id, buffer, length);
}

int luat_uart_close(int uart_id) {
    if (uart_id < 0 || uart_id >= 128) {
        return -1;
    }
    const luat_uart_drv_opts_t *drv = uart_drvs[uart_id];
    if (drv == NULL || drv->close == NULL) {
        return -1;
    }
    return drv->close(NULL, uart_id);
}
