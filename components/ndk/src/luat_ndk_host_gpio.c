#include "luat_ndk_host.h"

#include "luat_gpio.h"

enum {
    LUAT_NDK_GPIO_STATUS_HOST_ERROR = 15u,
    LUAT_NDK_GPIO_STATUS_OK = 0u,
    LUAT_NDK_GPIO_STATUS_BAD_PIN = 10u,
    LUAT_NDK_GPIO_STATUS_BAD_MODE = 11u,
    LUAT_NDK_GPIO_STATUS_BAD_PULL = 12u,
    LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE = 13u,
    LUAT_NDK_GPIO_STATUS_UNSUPPORTED = 14u
};

static uint32_t ndk_gpio_status_to_error(uint32_t status) {
    switch (status) {
    case LUAT_NDK_GPIO_STATUS_OK:
        return LUAT_NDK_HOST_ERR_NONE;
    case LUAT_NDK_GPIO_STATUS_UNSUPPORTED:
    case LUAT_NDK_GPIO_STATUS_HOST_ERROR:
        return LUAT_NDK_HOST_ERR_UNSUPPORTED;
    default:
        return LUAT_NDK_HOST_ERR_PARAM;
    }
}

static int ndk_gpio_mode_from_abi(uint32_t mode, int *host_mode) {
    if (!host_mode) return -1;
    switch (mode) {
    case LUAT_NDK_GPIO_MODE_INPUT:
        *host_mode = LUAT_GPIO_INPUT;
        return 0;
    case LUAT_NDK_GPIO_MODE_OUTPUT:
        *host_mode = LUAT_GPIO_OUTPUT;
        return 0;
    case LUAT_NDK_GPIO_MODE_IRQ:
        *host_mode = LUAT_GPIO_IRQ;
        return 0;
    default:
        return -1;
    }
}

static int ndk_gpio_pull_from_abi(uint32_t pull, int *host_pull) {
    if (!host_pull) return -1;
    switch (pull) {
    case LUAT_NDK_GPIO_PULL_DEFAULT:
        *host_pull = LUAT_GPIO_DEFAULT;
        return 0;
    case LUAT_NDK_GPIO_PULL_UP:
        *host_pull = LUAT_GPIO_PULLUP;
        return 0;
    case LUAT_NDK_GPIO_PULL_DOWN:
        *host_pull = LUAT_GPIO_PULLDOWN;
        return 0;
    default:
        return -1;
    }
}

static int ndk_gpio_irq_from_abi(uint32_t irq_mode, int *host_irq) {
    if (!host_irq) return -1;
    switch (irq_mode) {
    case LUAT_NDK_GPIO_IRQ_RISING:
        *host_irq = LUAT_GPIO_RISING_IRQ;
        return 0;
    case LUAT_NDK_GPIO_IRQ_FALLING:
        *host_irq = LUAT_GPIO_FALLING_IRQ;
        return 0;
    case LUAT_NDK_GPIO_IRQ_BOTH:
        *host_irq = LUAT_GPIO_BOTH_IRQ;
        return 0;
    case LUAT_NDK_GPIO_IRQ_HIGH:
        *host_irq = LUAT_GPIO_HIGH_IRQ;
        return 0;
    case LUAT_NDK_GPIO_IRQ_LOW:
        *host_irq = LUAT_GPIO_LOW_IRQ;
        return 0;
    default:
        return -1;
    }
}

static uint32_t ndk_gpio_validate_pin(uint32_t pin) {
    if (pin > LUAT_GPIO_PIN_MAX) {
        return LUAT_NDK_GPIO_STATUS_BAD_PIN;
    }
    return LUAT_NDK_GPIO_STATUS_OK;
}

uint32_t luat_ndk_gpio_csr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value) {
    uint32_t status = LUAT_NDK_GPIO_STATUS_UNSUPPORTED;

    if (!ctx) {
        return LUAT_NDK_GPIO_STATUS_HOST_ERROR;
    }

    switch (csrno) {
    case NDK_CSR_GPIO_CONFIG: {
        uint32_t pin = value & 0xFFu;
        uint32_t mode = (value >> 8) & 0xFFu;
        uint32_t pull = (value >> 16) & 0xFFu;
        uint32_t irq_mode = (value >> 24) & 0xFFu;
        int host_mode = 0;
        int host_pull = 0;
        int host_irq = 0;

        status = ndk_gpio_validate_pin(pin);
        if (status != LUAT_NDK_GPIO_STATUS_OK) break;
        if (ndk_gpio_mode_from_abi(mode, &host_mode) != 0) {
            status = LUAT_NDK_GPIO_STATUS_BAD_MODE;
            break;
        }
        if (ndk_gpio_pull_from_abi(pull, &host_pull) != 0) {
            status = LUAT_NDK_GPIO_STATUS_BAD_PULL;
            break;
        }
        if (mode == LUAT_NDK_GPIO_MODE_IRQ && ndk_gpio_irq_from_abi(irq_mode, &host_irq) != 0) {
            status = LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE;
            break;
        }
        if (mode == LUAT_NDK_GPIO_MODE_IRQ) {
            luat_gpio_cfg_t cfg = {0};
            cfg.pin = (int)pin;
            cfg.mode = host_mode;
            cfg.pull = host_pull;
            cfg.irq_type = host_irq;
            cfg.output_level = LUAT_GPIO_LOW;
            if (luat_gpio_open(&cfg) != 0) {
                status = LUAT_NDK_GPIO_STATUS_UNSUPPORTED;
                break;
            }
        }
        else {
            luat_gpio_mode((int)pin, host_mode, host_pull, LUAT_GPIO_LOW);
        }
        status = LUAT_NDK_GPIO_STATUS_OK;
        break;
    }
    case NDK_CSR_GPIO_WRITE_V2: {
        uint32_t pin = value & 0xFFFFu;
        uint32_t level = (value >> 16) & 0x1u;

        status = ndk_gpio_validate_pin(pin);
        if (status != LUAT_NDK_GPIO_STATUS_OK) break;
        luat_gpio_set((int)pin, (int)level);
        status = LUAT_NDK_GPIO_STATUS_OK;
        break;
    }
    case NDK_CSR_GPIO_READ_V2: {
        uint32_t pin = value & 0xFFFFu;
        int level = 0;

        status = ndk_gpio_validate_pin(pin);
        if (status != LUAT_NDK_GPIO_STATUS_OK) break;
        level = luat_gpio_get((int)pin);
        if (level != 0 && level != 1) {
            status = LUAT_NDK_GPIO_STATUS_UNSUPPORTED;
            break;
        }
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
        return (uint32_t)level;
    }
    case NDK_CSR_GPIO_IRQ_STATE:
    case NDK_CSR_GPIO_IRQ_CLEAR:
        status = LUAT_NDK_GPIO_STATUS_UNSUPPORTED;
        break;
    default:
        status = LUAT_NDK_GPIO_STATUS_UNSUPPORTED;
        break;
    }

    luat_ndk_event_set_last_error(ctx, (luat_ndk_host_err_t)ndk_gpio_status_to_error(status));
    return status;
}

void luat_ndk_gpio_reset(luat_ndk_t *ctx) {
    (void)ctx;
}
