#include "little_flash_ftl_internal.h"

static void little_flash_ftl_refresh_free_spares(little_flash_ftl_ctx_t *ctx) {
    uint32_t i = 0;
    uint32_t free_pages = 0;
    for (i = ctx->spare_begin; i < ctx->spare_end; i++) {
        if (!ctx->bad[i] && ctx->p2l[i] == LF_FTL_INVALID_PAGE) {
            free_pages++;
        }
    }
    ctx->free_spares = free_pages;
}

lf_err_t little_flash_ftl_gc_collect(little_flash_t *lf, uint8_t force) {
    little_flash_ftl_ctx_t *ctx = NULL;
    if (!lf || !lf->ftl_enabled || !lf->ftl_ctx) {
        return LF_ERR_OK;
    }
    ctx = (little_flash_ftl_ctx_t *)lf->ftl_ctx;
    little_flash_ftl_refresh_free_spares(ctx);
    if (!force && ctx->free_spares > ctx->gc_low_watermark && ctx->journal_count < (LF_FTL_JOURNAL_MAX / 2u)) {
        return LF_ERR_OK;
    }
    if (little_flash_ftl_meta_checkpoint(lf, ctx) != LF_ERR_OK) {
        return LF_ERR_ERASE;
    }
    ctx->journal_count = 0;
    return LF_ERR_OK;
}
