#include "little_flash_ftl_internal.h"
#include <string.h>

#define LF_FTL_META_MAGIC (0x4C46544Cu)

static uint32_t little_flash_ftl_crc32(const uint8_t *data, uint32_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    uint32_t i = 0;
    while (i < len) {
        uint32_t b = data[i++];
        uint32_t j = 0;
        crc ^= b;
        while (j++ < 8u) {
            uint32_t mask = (uint32_t)(-(int32_t)(crc & 1u));
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

static uint32_t little_flash_ftl_map_crc(const little_flash_ftl_ctx_t *ctx) {
    return little_flash_ftl_crc32((const uint8_t *)ctx->l2p, ctx->logical_pages * sizeof(uint32_t));
}

static int little_flash_ftl_checkpoint_valid(const little_flash_ftl_checkpoint_hdr_t *cp, const little_flash_ftl_ctx_t *ctx) {
    if (!cp || cp->magic != LF_FTL_META_MAGIC) {
        return 0;
    }
    if (cp->logical_pages != ctx->logical_pages) {
        return 0;
    }
    return cp->crc == little_flash_ftl_map_crc(ctx);
}

lf_err_t little_flash_ftl_meta_checkpoint(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    little_flash_ftl_checkpoint_hdr_t next;
    (void)lf;
    if (!ctx || !ctx->l2p) {
        return LF_ERR_BAD_ADDRESS;
    }
    memset(&next, 0, sizeof(next));
    next.magic = LF_FTL_META_MAGIC;
    next.logical_pages = ctx->logical_pages;
    next.generation = (ctx->cp_a.generation > ctx->cp_b.generation ? ctx->cp_a.generation : ctx->cp_b.generation) + 1u;
    next.crc = little_flash_ftl_map_crc(ctx);
    if ((next.generation & 1u) == 0u) {
        ctx->cp_a = next;
    } else {
        ctx->cp_b = next;
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_meta_append_journal(little_flash_t *lf, little_flash_ftl_ctx_t *ctx, uint32_t logical_page, uint32_t physical_page) {
    (void)lf;
    if (!ctx || ctx->journal_count >= LF_FTL_JOURNAL_MAX) {
        return LF_ERR_NO_MEM;
    }
    ctx->journal[ctx->journal_count].logical_page = logical_page;
    ctx->journal[ctx->journal_count].physical_page = physical_page;
    ctx->journal_count++;
    return LF_ERR_OK;
}

lf_err_t little_flash_ftl_meta_recover(little_flash_t *lf, little_flash_ftl_ctx_t *ctx) {
    uint32_t i = 0;
    (void)lf;
    if (!ctx || !ctx->l2p) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (!little_flash_ftl_checkpoint_valid(&ctx->cp_a, ctx) && !little_flash_ftl_checkpoint_valid(&ctx->cp_b, ctx)) {
        return LF_ERR_READ;
    }
    for (i = 0; i < ctx->journal_count; i++) {
        uint32_t l = ctx->journal[i].logical_page;
        uint32_t p = ctx->journal[i].physical_page;
        uint32_t old_p = 0;
        if (l >= ctx->logical_pages || p >= ctx->page_count || ctx->bad[p]) {
            return LF_ERR_BAD_ADDRESS;
        }
        old_p = ctx->l2p[l];
        if (old_p < ctx->page_count && old_p != p && ctx->p2l[old_p] == l) {
            ctx->p2l[old_p] = LF_FTL_INVALID_PAGE;
        }
        ctx->l2p[l] = p;
        ctx->p2l[p] = l;
    }
    return LF_ERR_OK;
}
