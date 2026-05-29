#include "little_flash_ftl_internal.h"
#include "luat_malloc.h"
#include <string.h>

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
    uint32_t min_reserve = 0;
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
    ctx->reserve_pages = (ctx->page_count * op_percent) / 100;
    min_reserve = pages_per_block * 2u + 8u; /* two metadata blocks + spare pool */
    if (ctx->reserve_pages < min_reserve) {
        ctx->reserve_pages = min_reserve;
    }
    if (ctx->reserve_pages > (ctx->page_count / 2)) {
        ctx->reserve_pages = ctx->page_count / 2;
    }
    ctx->logical_pages = ctx->page_count - ctx->reserve_pages;
    ctx->spare_begin = ctx->logical_pages;
    ctx->spare_end = ctx->page_count - (pages_per_block * 2u);
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
    for (i = 0; i < ctx->logical_pages; i++) {
        ctx->l2p[i] = i;
        ctx->p2l[i] = i;
    }
    ctx->free_spares = ctx->spare_end - ctx->spare_begin;
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
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_BAD_ADDRESS;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    if (logical_page >= ctx->logical_pages || bad_physical_page >= ctx->page_count) {
        return LF_ERR_BAD_ADDRESS;
    }
    ctx->p2l[bad_physical_page] = LF_FTL_INVALID_PAGE;
    ctx->bad[bad_physical_page] = 1;
    if (little_flash_ftl_find_spare(ctx, &spare_page) != 0) {
        return LF_ERR_ERASE;
    }
    ctx->p2l[ctx->l2p[logical_page]] = LF_FTL_INVALID_PAGE;
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
    return -1;
}
#endif
