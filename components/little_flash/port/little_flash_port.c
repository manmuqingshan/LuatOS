
#include "little_flash.h"

#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_spi.h"

static lf_err_t little_flash_spi_transfer(const little_flash_t *lf,uint8_t *tx_buf, uint32_t tx_len, uint8_t *rx_buf, uint32_t rx_len){
    lf_err_t result = LF_ERR_OK;
    luat_spi_device_t *spi_dev = (luat_spi_device_t*)lf->spi.user_data;
    if (tx_len && rx_len) {
        if (luat_spi_device_transfer(spi_dev , (const char*)tx_buf, tx_len, (char*)rx_buf, rx_len) <= 0) {
            result = LF_ERR_TRANSFER;
        }
    } else if (tx_buf) {
        if (luat_spi_device_send(spi_dev ,  (const char*)tx_buf, tx_len) <= 0) {
            result = LF_ERR_WRITE;
        }
    } else {
        if (luat_spi_device_recv(spi_dev , (char*)rx_buf, rx_len) <= 0) {
            result = LF_ERR_READ;
        }
    }
    return result;
}

static void little_flash_wait_10us(uint32_t count){
    uint32_t delay = 12*count;
    while(delay--);
}

static void little_flash_wait_ms(uint32_t ms){
    luat_rtos_task_sleep(ms);
}

#ifdef LF_USE_HEAP
static void* little_flash_malloc(size_t size){
    return luat_heap_opt_malloc(LUAT_HEAP_SRAM,size);
}

static void little_flash_free(void* ptr){
    luat_heap_opt_free(LUAT_HEAP_AUTO,ptr);
}
#endif

static void little_flash_lock(little_flash_t *lf){
    luat_mutex_lock(lf->user_data);
}

static void little_flash_unlock(little_flash_t *lf){
    luat_mutex_unlock(lf->user_data);
}

lf_err_t little_flash_port_init(little_flash_t *lf){
    lf->spi.transfer = little_flash_spi_transfer;
    lf->wait_10us = little_flash_wait_10us;
    lf->wait_ms = little_flash_wait_ms;
#ifdef LF_USE_HEAP
    lf->malloc = little_flash_malloc;
    lf->free = little_flash_free;
#endif
    /* create a mutex for locking */
    lf->user_data = luat_mutex_create();
    lf->lock = little_flash_lock;
    lf->unlock = little_flash_unlock;
    return LF_ERR_OK;
}
























