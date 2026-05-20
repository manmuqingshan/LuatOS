#include "luat_ndk_host.h"

#include <string.h>

#include "luat_uart.h"

static uint32_t ndk_uart_validate_port(uint32_t port) {
    return port == LUAT_VUART_ID_0 ? LUAT_NDK_UART_STATUS_OK : LUAT_NDK_UART_STATUS_BAD_PORT;
}

uint32_t luat_ndk_uart_csr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value) {
    uint32_t port = 0;

    if (!ctx) return LUAT_NDK_UART_STATUS_HOST_ERROR;

    switch (csrno) {
    case NDK_CSR_UART_CONFIG: {
        uint32_t cfg_offset = LUAT_NDK_UART_PTR_OFFSET(value);
        port = LUAT_NDK_UART_PTR_PORT(value);
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        ctx->uart_ports[0].configured = 1;
        ctx->uart_ports[0].port_id = port;
        // cfg_offset recorded for Task 3: the cfg struct at exchange[cfg_offset]
        // will be read and applied to baud/data_bits/stop_bits/parity/rx_enable.
        (void)cfg_offset;
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_STATUS_OK;
    }

    case NDK_CSR_UART_TX:
        port = LUAT_NDK_UART_IO_PORT(value);
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_STATUS_OK;

    case NDK_CSR_UART_RX_STATE:
        port = value & 0xFFu;
        if (ndk_uart_validate_port(port) != LUAT_NDK_UART_STATUS_OK) {
            luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
            return LUAT_NDK_UART_STATUS_BAD_PORT;
        }
        // Return a zero-packed state: pending=0, buffered_len=0, reason=0.
        // Full buffering is wired in Task 3.
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return LUAT_NDK_UART_RX_STATE_PACK(0, 0, 0);

    default:
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_UNSUPPORTED);
        return LUAT_NDK_UART_STATUS_UNSUPPORTED;
    }
}

void luat_ndk_uart_reset(luat_ndk_t *ctx) {
    if (!ctx) return;
    memset(ctx->uart_ports, 0, sizeof(ctx->uart_ports));
}
