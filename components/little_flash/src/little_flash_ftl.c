#include "little_flash_ftl_internal.h"
#include "luat_malloc.h"
#include <string.h>

static lf_err_t little_flash_ftl_wait_ready(const little_flash_t *lf, uint32_t timeout_us) {
    uint8_t status = 0;
    uint32_t waited = 0;
    lf_err_t ret;
    if (!lf) {
        return LF_ERR_BAD_ADDRESS;
    }
    while (waited < timeout_us) {
        ret = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        if (ret != LF_ERR_OK) {
            return ret;
        }
        if ((status & LF_STATUS_REGISTER_BUSY) == 0) {
            return LF_ERR_OK;
        }
        if (lf->wait_10us) {
            lf->wait_10us(1);
        }
        waited += 10u;
    }
    return LF_ERR_TIMEOUT;
}

static lf_err_t little_flash_ftl_read_oob_marker(const little_flash_t *lf, uint32_t page_addr, uint8_t *marker) {
    uint8_t cmd_data[4];
    lf_err_t ret;
    if (!lf || !marker) {
        return LF_ERR_BAD_ADDRESS;
    }
    cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
    cmd_data[1] = (uint8_t)(page_addr >> 16);
    cmd_data[2] = (uint8_t)(page_addr >> 8);
    cmd_data[3] = (uint8_t)(page_addr);
    ret = lf->spi.transfer(lf, cmd_data, 4, LF_NULL, 0);
    if (ret != LF_ERR_OK) {
        return ret;
    }
    ret = little_flash_ftl_wait_ready(lf, 1000u);
    if (ret != LF_ERR_OK) {
        return ret;
    }
    cmd_data[0] = LF_CMD_READ_DATA;
    cmd_data[1] = (uint8_t)(lf->chip_info.read_size >> 8);
    cmd_data[2] = (uint8_t)(lf->chip_info.read_size);
    cmd_data[3] = 0;
    return lf->spi.transfer(lf, cmd_data, 4, marker, 1);
}

static void little_flash_ftl_mark_bad_block(little_flash_ftl_ctx_t *ctx, uint32_t block_index) {
    uint32_t start = block_index * ctx->pages_per_block;
    uint32_t end = start + ctx->pages_per_block;
    uint32_t i;
    for (i = start; i < end && i < ctx->page_count; i++) {
        ctx->bad[i] = 1;
    }
}

static void little_flash_ftl_scan_bad_blocks(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    uint32_t block_index;
    if (!lf || !ctx || !lf->spi.transfer) {
        return;
    }
    for (block_index = 0; block_index < ctx->block_count; block_index++) {
        uint32_t first_page = block_index * ctx->pages_per_block;
        uint32_t second_page = first_page + 1u;
        uint8_t marker0 = 0xFF;
        uint8_t marker1 = 0xFF;
        int is_bad = 0;
        if (little_flash_ftl_read_oob_marker(lf, first_page, &marker0) != LF_ERR_OK) {
            is_bad = 1;
        }
        if (!is_bad && second_page < ctx->page_count &&
            little_flash_ftl_read_oob_marker(lf, second_page, &marker1) != LF_ERR_OK) {
            is_bad = 1;
        }
        if (!is_bad && (marker0 != 0xFF || marker1 != 0xFF)) {
            is_bad = 1;
        }
        if (is_bad) {
            little_flash_ftl_mark_bad_block(ctx, block_index);
            ctx->bad_blocks++;
            ctx->bad_pages += ctx->pages_per_block;
        }
    }
}

static int little_flash_ftl_page_used(const little_flash_ftl_ctx_t *ctx, uint32_t page) {
    return ctx->p2l[page] != LF_FTL_INVALID_PAGE;
}

static int little_flash_ftl_find_spare(const little_flash_ftl_ctx_t *ctx, uint32_t *page) {
    uint32_t start = 0;
    uint32_t i = 0;
    if (ctx->reserve_pages == 0 || ctx->reserve_pages >= ctx->page_count) {
        return -1;
    }
    start = ctx->spare_begin;
    for (i = start; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && !little_flash_ftl_page_used(ctx, i)) {
            *page = i;
            return 0;
        }
    }
    return -1;
}

lf_err_t little_flash_ftl_init(little_flash_t *lf, uint8_t op_percent) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t pages_per_block = 0;
    uint32_t metadata_pages = 0;
    uint32_t min_reserve = 0;
    uint32_t good_pages = 0;
    uint32_t logical_target = 0;
    uint32_t i = 0;
    if (!lf || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return LF_ERR_OK;
    }
    if (lf->chip_info.read_size == 0) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!lf->malloc || !lf->free) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->malloc(sizeof(little_flash_ftl_ctx_t));
    if (!ctx) {
        return LF_ERR_NO_MEM;
    }
    memset(ctx, 0, sizeof(*ctx));
    ctx->raw_capacity = lf->chip_info.capacity;
    ctx->page_count = lf->chip_info.capacity / lf->chip_info.read_size;
    pages_per_block = lf->chip_info.erase_size / lf->chip_info.read_size;
    metadata_pages = pages_per_block * 2u;
    if (ctx->page_count <= metadata_pages || pages_per_block == 0) {
        lf->free(ctx);
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->pages_per_block = pages_per_block;
    ctx->block_count = ctx->page_count / pages_per_block;
    ctx->reserve_pages = ((ctx->page_count - metadata_pages) * op_percent) / 100;
    min_reserve = 8u;
    if (ctx->reserve_pages < min_reserve) {
        ctx->reserve_pages = min_reserve;
    }
    if (ctx->reserve_pages > ((ctx->page_count - metadata_pages) / 2u)) {
        ctx->reserve_pages = (ctx->page_count - metadata_pages) / 2u;
    }
    ctx->spare_begin = 0;
    ctx->spare_end = ctx->page_count - metadata_pages;
    if (ctx->spare_begin >= ctx->spare_end) {
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    ctx->gc_low_watermark = 2u;
    ctx->gc_high_watermark = 6u;
    ctx->l2p = (uint32_t *)lf->malloc(sizeof(uint32_t) * ctx->page_count);
    ctx->p2l = (uint32_t *)lf->malloc(sizeof(uint32_t) * ctx->page_count);
    ctx->bad = (uint8_t *)lf->malloc(ctx->page_count);
    if (!ctx->l2p || !ctx->p2l || !ctx->bad) {
        if (ctx->l2p) {
            lf->free(ctx->l2p);
        }
        if (ctx->p2l) {
            lf->free(ctx->p2l);
        }
        if (ctx->bad) {
            lf->free(ctx->bad);
        }
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    memset(ctx->bad, 0, ctx->page_count);
    for (i = 0; i < ctx->page_count; i++) {
        ctx->p2l[i] = LF_FTL_INVALID_PAGE;
    }
    little_flash_ftl_scan_bad_blocks(lf, ctx);
    for (i = 0; i < ctx->spare_end; i++) {
        if (!ctx->bad[i]) {
            good_pages++;
        }
    }
    if (good_pages <= ctx->reserve_pages) {
        lf->free(ctx->bad);
        lf->free(ctx->p2l);
        lf->free(ctx->l2p);
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    logical_target = good_pages - ctx->reserve_pages;
    ctx->logical_pages = 0;
    for (i = 0; i < ctx->spare_end && ctx->logical_pages < logical_target; i++) {
        if (!ctx->bad[i]) {
            ctx->l2p[ctx->logical_pages] = i;
            ctx->p2l[i] = ctx->logical_pages;
            ctx->logical_pages++;
        }
    }
    ctx->free_spares = 0;
    for (i = 0; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && !little_flash_ftl_page_used(ctx, i)) {
            ctx->free_spares++;
        }
    }
    if (little_flash_ftl_meta_checkpoint(lf, ctx) != LF_ERR_OK) {
        lf->free(ctx->bad);
        lf->free(ctx->p2l);
        lf->free(ctx->l2p);
        lf->free(ctx);
        return LF_ERR_NO_MEM;
    }
    lf->ftl_ctx = ctx;
    lf->ftl_enabled = 1;
    lf->chip_info.capacity = ctx->logical_pages * lf->chip_info.read_size;
    LF_INFO("little_flash ftl init: blocks=%lu bad_blocks=%lu bad_pages=%lu logical_pages=%lu reserve_pages=%lu",
            (unsigned long)ctx->block_count,
            (unsigned long)ctx->bad_blocks,
            (unsigned long)ctx->bad_pages,
            (unsigned long)ctx->logical_pages,
            (unsigned long)ctx->reserve_pages);
    LF_INFO("little_flash ftl space: usable=%lu bytes reserve_free=%lu bytes reserve_total=%lu bytes raw=%lu bytes",
            (unsigned long)(ctx->logical_pages * lf->chip_info.read_size),
            (unsigned long)(ctx->free_spares * lf->chip_info.read_size),
            (unsigned long)(ctx->reserve_pages * lf->chip_info.read_size),
            (unsigned long)ctx->raw_capacity);
    return LF_ERR_OK;
}

void little_flash_ftl_deinit(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t raw_capacity = 0;
    if (!lf || !lf->ftl_ctx || !lf->free) {
        return;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    raw_capacity = ctx->raw_capacity;
    if (ctx->l2p) {
        lf->free(ctx->l2p);
    }
    if (ctx->p2l) {
        lf->free(ctx->p2l);
    }
    if (ctx->bad) {
        lf->free(ctx->bad);
    }
    lf->free(ctx);
    if (lf->chip_info.type == LF_DRIVER_NAND_FLASH && raw_capacity) {
        lf->chip_info.capacity = raw_capacity;
    }
    if (lf) {
        lf->ftl_ctx = NULL;
        lf->ftl_enabled = 0;
    }
}

lf_err_t little_flash_ftl_map_page(const little_flash_t *lf, uint32_t logical_page, uint32_t *physical_page) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !physical_page) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!lf->ftl_enabled || !lf->ftl_ctx || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        *physical_page = logical_page;
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    if (logical_page >= ctx->logical_pages) {
        return LF_ERR_BAD_ADDRESS;
    }
    *physical_page = ctx->l2p[logical_page];
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_mark_bad_and_remap(little_flash_t *lf, uint32_t logical_page, uint32_t bad_physical_page) {
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t spare_page = 0;
    uint32_t current_physical = 0;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_BAD_ADDRESS;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    if (logical_page >= ctx->logical_pages || bad_physical_page >= ctx->page_count) {
        return LF_ERR_BAD_ADDRESS;
    }
    current_physical = ctx->l2p[logical_page];
    if (current_physical >= ctx->page_count) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (ctx->bad[bad_physical_page]) {
        if (current_physical != bad_physical_page) {
            return LF_ERR_OK;
        }
    }
    if (current_physical != bad_physical_page) {
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->p2l[bad_physical_page] = LF_FTL_INVALID_PAGE;
    ctx->bad[bad_physical_page] = 1;
    if (little_flash_ftl_find_spare(ctx, &spare_page) != 0) {
        return LF_ERR_ERASE;
    }
    ctx->p2l[current_physical] = LF_FTL_INVALID_PAGE;
    ctx->l2p[logical_page] = spare_page;
    ctx->p2l[spare_page] = logical_page;
    if (little_flash_ftl_meta_append_journal(lf, ctx, logical_page, spare_page) != LF_ERR_OK) {
        return LF_ERR_ERASE;
    }
    if (ctx->free_spares > 0) {
        ctx->free_spares--;
    }
    if (ctx->free_spares <= ctx->gc_low_watermark) {
        little_flash_ftl_gc_collect(lf, 0);
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_sync(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    return little_flash_ftl_meta_checkpoint(lf, ctx);
}

lf_err_t little_flash_ftl_recover(little_flash_t *lf) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    return little_flash_ftl_meta_recover(lf, ctx);
}

#ifdef LUAT_USE_UTEST
static int little_flash_ftl_utest_identity_map(void) {
    little_flash_t lf;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    {
        little_flash_ftl_ctx_t *ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
        uint32_t i = 0;
        for (i = 0; i < ctx->logical_pages; i++) {
            uint32_t p = 0;
            if (little_flash_ftl_map_page(&lf, i, &p) != LF_ERR_OK || p != i) {
                little_flash_ftl_deinit(&lf);
                return -1;
            }
        }
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_badblock_remap(void) {
    little_flash_t lf;
    uint32_t p = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf, 5, 5) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf, 5, &p) != LF_ERR_OK || p == 5) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_powerfail_recovery(void) {
    little_flash_t lf;
    uint32_t p = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    if (little_flash_ftl_mark_bad_and_remap(&lf, 9, 9) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_sync(&lf) != LF_ERR_OK || little_flash_ftl_recover(&lf) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (little_flash_ftl_map_page(&lf, 9, &p) != LF_ERR_OK || p == 9) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_gc_trigger(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    ctx->journal_count = LF_FTL_JOURNAL_MAX - 1u;
    if (little_flash_ftl_gc_collect(&lf, 0) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->journal_count != 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

typedef enum {
    LF_UTEST_FAULT_NONE = 0,
    LF_UTEST_FAULT_BLOCK1_BAD,
    LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0,
    LF_UTEST_FAULT_STATUS_BUSY_ALWAYS
} little_flash_ftl_utest_fault_t;

typedef struct {
    little_flash_ftl_utest_fault_t fault;
    uint32_t current_page;
} little_flash_ftl_utest_state_t;

static little_flash_ftl_utest_state_t g_lf_ftl_utest_state;

static void little_flash_ftl_utest_state_reset(little_flash_ftl_utest_fault_t fault) {
    memset(&g_lf_ftl_utest_state, 0, sizeof(g_lf_ftl_utest_state));
    g_lf_ftl_utest_state.fault = fault;
}

static void little_flash_ftl_utest_wait_10us(uint32_t count) {
    (void)count;
}

static lf_err_t little_flash_ftl_utest_spi_transfer(const little_flash_t *lf, uint8_t *tx_buf, uint32_t tx_len, uint8_t *rx_buf, uint32_t rx_len) {
    (void)lf;
    if (!tx_buf) {
        return LF_ERR_TRANSFER;
    }
    if (tx_buf[0] == LF_NANDFLASH_PAGE_DATA_READ && tx_len >= 4) {
        g_lf_ftl_utest_state.current_page = ((uint32_t)tx_buf[1] << 16) | ((uint32_t)tx_buf[2] << 8) | tx_buf[3];
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_NANDFLASH_READ_STATUS_REGISTER && tx_len >= 2 && rx_buf && rx_len >= 1) {
        if (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_STATUS_BUSY_ALWAYS) {
            rx_buf[0] = LF_STATUS_REGISTER_BUSY;
        } else {
            rx_buf[0] = 0;
        }
        return LF_ERR_OK;
    }
    if (tx_buf[0] == LF_CMD_READ_DATA && tx_len >= 4 && rx_buf && rx_len >= 1) {
        uint32_t block = g_lf_ftl_utest_state.current_page / 64u;
        if (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0 && block == 0u) {
            return LF_ERR_TRANSFER;
        }
        if (g_lf_ftl_utest_state.fault == LF_UTEST_FAULT_BLOCK1_BAD && block == 1u) {
            rx_buf[0] = 0x00;
        } else {
            rx_buf[0] = 0xFF;
        }
        return LF_ERR_OK;
    }
    return LF_ERR_OK;
}

static void little_flash_ftl_utest_prepare_lf(little_flash_t *lf, little_flash_ftl_utest_fault_t fault) {
    memset(lf, 0, sizeof(*lf));
    little_flash_ftl_utest_state_reset(fault);
    lf->chip_info.type = LF_DRIVER_NAND_FLASH;
    lf->chip_info.capacity = 2048 * 512;
    lf->chip_info.read_size = 2048;
    lf->chip_info.erase_size = 131072;
    lf->malloc = luat_heap_malloc;
    lf->free = luat_heap_free;
    lf->wait_10us = little_flash_ftl_utest_wait_10us;
    lf->spi.transfer = little_flash_ftl_utest_spi_transfer;
}

static int little_flash_ftl_utest_init_stats(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_BLOCK1_BAD);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx || ctx->bad_blocks != 1u || ctx->logical_pages == 0u || ctx->free_spares == 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_oob_read_error_scan(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_OOB_READ_FAIL_BLOCK0);
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (!ctx || ctx->bad_blocks == 0u) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_wait_ready_timeout(void) {
    little_flash_t lf;
    little_flash_ftl_utest_prepare_lf(&lf, LF_UTEST_FAULT_STATUS_BUSY_ALWAYS);
    return little_flash_ftl_wait_ready(&lf, 50u) == LF_ERR_TIMEOUT ? 0 : -1;
}

static int little_flash_ftl_utest_recover_crc_invalid(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    ctx->cp_a.crc ^= 0x12345678u;
    ctx->cp_b.crc ^= 0x87654321u;
    if (little_flash_ftl_recover(&lf) != LF_ERR_READ) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_recover_journal_out_of_range(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    ctx->journal_count = 1;
    ctx->journal[0].logical_page = ctx->logical_pages + 1u;
    ctx->journal[0].physical_page = 0u;
    if (little_flash_ftl_recover(&lf) != LF_ERR_BAD_ADDRESS) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

static int little_flash_ftl_utest_repeat_mark_bad_idempotent(void) {
    little_flash_t lf;
    little_flash_ftl_ctx_t *ctx = NULL;
    uint32_t first_mapping = 0;
    uint32_t free_spares_before = 0;
    memset(&lf, 0, sizeof(lf));
    lf.chip_info.type = LF_DRIVER_NAND_FLASH;
    lf.chip_info.capacity = 2048 * 512;
    lf.chip_info.read_size = 2048;
    lf.chip_info.erase_size = 131072;
    lf.malloc = luat_heap_malloc;
    lf.free = luat_heap_free;
    if (little_flash_ftl_init(&lf, 15) != LF_ERR_OK) {
        return -1;
    }
    ctx = (little_flash_ftl_ctx_t *)lf.ftl_ctx;
    if (little_flash_ftl_mark_bad_and_remap(&lf, 7, 7) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    first_mapping = ctx->l2p[7];
    free_spares_before = ctx->free_spares;
    if (little_flash_ftl_mark_bad_and_remap(&lf, 7, 7) != LF_ERR_OK) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    if (ctx->l2p[7] != first_mapping || ctx->free_spares != free_spares_before) {
        little_flash_ftl_deinit(&lf);
        return -1;
    }
    little_flash_ftl_deinit(&lf);
    return 0;
}

int little_flash_ftl_utest_case(const char *case_name) {
    if (!case_name || strcmp(case_name, "ftl_identity_map") == 0) {
        return little_flash_ftl_utest_identity_map();
    }
    if (strcmp(case_name, "ftl_badblock_remap") == 0) {
        return little_flash_ftl_utest_badblock_remap();
    }
    if (strcmp(case_name, "ftl_powerfail_recovery") == 0) {
        return little_flash_ftl_utest_powerfail_recovery();
    }
    if (strcmp(case_name, "ftl_gc_trigger") == 0) {
        return little_flash_ftl_utest_gc_trigger();
    }
    if (strcmp(case_name, "ftl_init_stats") == 0) {
        return little_flash_ftl_utest_init_stats();
    }
    if (strcmp(case_name, "ftl_oob_read_error_scan") == 0) {
        return little_flash_ftl_utest_oob_read_error_scan();
    }
    if (strcmp(case_name, "ftl_wait_ready_timeout") == 0) {
        return little_flash_ftl_utest_wait_ready_timeout();
    }
    if (strcmp(case_name, "ftl_recover_crc_invalid") == 0) {
        return little_flash_ftl_utest_recover_crc_invalid();
    }
    if (strcmp(case_name, "ftl_recover_journal_out_of_range") == 0) {
        return little_flash_ftl_utest_recover_journal_out_of_range();
    }
    if (strcmp(case_name, "ftl_repeat_mark_bad_idempotent") == 0) {
        return little_flash_ftl_utest_repeat_mark_bad_idempotent();
    }
    return -1;
}
#endif
