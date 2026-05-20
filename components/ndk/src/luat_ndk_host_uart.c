#include "luat_ndk_host.h"

#include <string.h>

#include "luat_uart.h"

static uint32_t ndk_uart_validate_port(uint32_t port) {
    return port == LUAT_VUART_ID_0 ? LUAT_NDK_UART_STATUS_OK : LUAT_NDK_UART_STATUS_BAD_PORT;
}

static void ndk_uart_port_reset(luat_ndk_uart_port_t *port) {
    memset(port, 0, sizeof(*port));
}

void luat_ndk_uart_reset(luat_ndk_t *ctx) {
    if (!ctx) return;
    ndk_uart_port_reset(&ctx->uart_ports[0]);
}

static int ndk_uart_rx_push(luat_ndk_uart_port_t *port, const uint8_t *data, uint16_t len) {
    uint16_t i = 0;
    if (port->rx_len + len > LUAT_NDK_UART_RX_CAPACITY) return -1;
    for (i = 0; i < len; i++) {
        port->rx_buf[port->rx_tail] = data[i];
        port->rx_tail = (uint16_t)((port->rx_tail + 1) % LUAT_NDK_UART_RX_CAPACITY);
    }
    port->rx_len = (uint16_t)(port->rx_len + len);
    return 0;
}

static uint16_t ndk_uart_rx_pop(luat_ndk_uart_port_t *port, uint8_t *out, uint16_t len) {
    uint16_t copied = 0;
    while (copied < len && port->rx_len > 0) {
        out[copied++] = port->rx_buf[port->rx_head];
        port->rx_head = (uint16_t)((port->rx_head + 1) % LUAT_NDK_UART_RX_CAPACITY);
        port->rx_len--;
    }
    return copied;
}

uint32_t luat_ndk_uart_csr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value) {
    if (!ctx) return LUAT_NDK_UART_STATUS_HOST_ERROR;

    switch (csrno) {
    case NDK_CSR_UART_CONFIG: {
        uint32_t cfg_offset = LUAT_NDK_UART_PTR_OFFSET(value);
        uint32_t port = LUAT_NDK_UART_PTR_PORT(value);
        const luat_ndk_uart_cfg_t *cfg = NULL;
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        if (cfg_offset + sizeof(luat_ndk_uart_cfg_t) > ctx->exchange_size) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_LENGTH;
        }
        cfg = (const luat_ndk_uart_cfg_t *)(ctx->ram + ctx->exchange_offset + cfg_offset);
        ctx->uart_ports[0].configured = 1;
        ctx->uart_ports[0].port_id = port;
        ctx->uart_ports[0].baud = cfg->baud;
        ctx->uart_ports[0].data_bits = cfg->data_bits;
        ctx->uart_ports[0].stop_bits = cfg->stop_bits;
        ctx->uart_ports[0].parity = cfg->parity;
        ctx->uart_ports[0].rx_enable = cfg->rx_enable;
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_STATUS_OK;
    }

    case NDK_CSR_UART_TX: {
        uint32_t port = LUAT_NDK_UART_IO_PORT(value);
        uint32_t offset = LUAT_NDK_UART_IO_OFFSET(value);
        uint32_t length = LUAT_NDK_UART_IO_LENGTH(value);
        luat_ndk_uart_port_t *uart = &ctx->uart_ports[0];
        uint8_t *src = NULL;
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        if (!uart->configured) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_CONFIG;
        }
        if (length == 0 || offset + length > ctx->exchange_size) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_LENGTH;
        }
        src = ctx->ram + ctx->exchange_offset + offset;
        if (uart->rx_enable) {
            if (ndk_uart_rx_push(uart, src, (uint16_t)length) != 0) {
                luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
                return LUAT_NDK_UART_STATUS_OVERFLOW;
            }
            uart->pending = 1;
            uart->reason = 1; /* loopback-ready */
            luat_ndk_event_push(ctx, LUAT_NDK_EVENT_UART_RX_READY, (uint16_t)port,
                LUAT_NDK_UART_RX_STATE_PACK(uart->pending, uart->rx_len, uart->reason));
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_STATUS_OK;
    }

    case NDK_CSR_UART_RX_STATE: {
        uint32_t port = value & 0xFFu;
        luat_ndk_uart_port_t *uart = &ctx->uart_ports[0];
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        if (!uart->configured) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_CONFIG;
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_RX_STATE_PACK(uart->pending, uart->rx_len, uart->reason);
    }

    case NDK_CSR_UART_RX_READ: {
        uint32_t port = LUAT_NDK_UART_IO_PORT(value);
        uint32_t offset = LUAT_NDK_UART_IO_OFFSET(value);
        uint32_t length = LUAT_NDK_UART_IO_LENGTH(value);
        luat_ndk_uart_port_t *uart = &ctx->uart_ports[0];
        uint16_t copied = 0;
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        if (!uart->configured) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_CONFIG;
        }
        if (length == 0 || offset + length > ctx->exchange_size) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_LENGTH;
        }
        copied = ndk_uart_rx_pop(uart, ctx->ram + ctx->exchange_offset + offset, (uint16_t)length);
        if (uart->rx_len == 0) {
            uart->pending = 0;
            uart->reason = 0;
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return copied;
    }

    case NDK_CSR_UART_RX_CLEAR: {
        uint32_t port = value & 0xFFu;
        luat_ndk_uart_port_t *uart = &ctx->uart_ports[0];
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        if (!uart->configured) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_CONFIG;
        }
        uart->pending = 0;
        uart->reason = 0;
        uart->rx_len = 0;
        uart->rx_head = 0;
        uart->rx_tail = 0;
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_STATUS_OK;
    }

    default:
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_UNSUPPORTED);
        return LUAT_NDK_UART_STATUS_UNSUPPORTED;
    }
}
