
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#ifdef LUAT_USE_FS_VFS
#ifdef LUAT_USE_LFSV3_COMPONENT

#include "lfs3.h"
#include "little_flash.h"

#define LFS3_LF_LOOKAHEAD_SIZE 16

typedef struct {
    lfs3_t          lfs3;
    struct lfs3_cfg cfg;
    little_flash_t *flash;
    size_t          offset;
    uint8_t        *rcache_buffer;
    uint8_t        *pcache_buffer;
    uint8_t         lookahead_buffer[LFS3_LF_LOOKAHEAD_SIZE];
} lf_lfs3_ctx_t;

static int lf3_read(const struct lfs3_cfg *cfg, lfs3_block_t block,
                    lfs3_off_t off, void *buffer, lfs3_size_t size) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_read(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size + (size_t)off),
        (uint8_t *)buffer, (uint32_t)size);
}

static int lf3_prog(const struct lfs3_cfg *cfg, lfs3_block_t block,
                    lfs3_off_t off, const void *buffer, lfs3_size_t size) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_write(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size + (size_t)off),
        (const uint8_t *)buffer, (uint32_t)size);
}

static int lf3_erase(const struct lfs3_cfg *cfg, lfs3_block_t block) {
    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)cfg->context;
    return little_flash_erase(ctx->flash,
        (uint32_t)(ctx->offset + (size_t)block * ctx->flash->chip_info.erase_size),
        (uint32_t)ctx->flash->chip_info.erase_size);
}

static int lf3_sync(const struct lfs3_cfg *cfg) {
    (void)cfg;
    return LFS3_ERR_OK;
}

lfs3_t *flash_lfs3_lf(little_flash_t *flash, size_t offset, size_t maxsize) {
    if (flash == NULL) {
        LLOGE("flash is null");
        return NULL;
    }

    lf_lfs3_ctx_t *ctx = (lf_lfs3_ctx_t *)luat_heap_malloc(sizeof(lf_lfs3_ctx_t));
    if (ctx == NULL)
        return NULL;
    memset(ctx, 0, sizeof(lf_lfs3_ctx_t));

    ctx->flash  = flash;
    ctx->offset = offset;

    lfs3_size_t cache_size = (lfs3_size_t)flash->chip_info.prog_size;

    ctx->rcache_buffer = (uint8_t *)luat_heap_malloc(cache_size);
    ctx->pcache_buffer = (uint8_t *)luat_heap_malloc(cache_size);
    if (ctx->rcache_buffer == NULL || ctx->pcache_buffer == NULL) {
        luat_heap_free(ctx->rcache_buffer);
        luat_heap_free(ctx->pcache_buffer);
        luat_heap_free(ctx);
        return NULL;
    }

    struct lfs3_cfg *cfg = &ctx->cfg;
    cfg->context      = ctx;
    cfg->read         = lf3_read;
    cfg->prog         = lf3_prog;
    cfg->erase        = lf3_erase;
    cfg->sync         = lf3_sync;

    cfg->read_size    = (lfs3_size_t)flash->chip_info.read_size;
    cfg->prog_size    = (lfs3_size_t)flash->chip_info.prog_size;
    cfg->block_size   = (lfs3_size_t)flash->chip_info.erase_size;
    cfg->block_count  = (lfs3_block_t)(
        (maxsize > 0 ? maxsize : (flash->chip_info.capacity - offset))
        / flash->chip_info.erase_size);

    cfg->block_recycles   = 200;
    cfg->rcache_size      = cache_size;
    cfg->pcache_size      = cache_size;
    cfg->fcache_size      = cache_size;
    cfg->lookahead_size   = LFS3_LF_LOOKAHEAD_SIZE;
    cfg->rcache_buffer    = ctx->rcache_buffer;
    cfg->pcache_buffer    = ctx->pcache_buffer;
    cfg->lookahead_buffer = ctx->lookahead_buffer;
    cfg->name_limit       = 63;
    cfg->file_limit       = 0;

    int err = lfs3_mount(&ctx->lfs3, 0, cfg);
    LLOGD("lfs3_mount %d", err);
    if (err) {
        err = lfs3_format(&ctx->lfs3, 0, cfg);
        LLOGD("lfs3_format %d", err);
        if (err)
            goto fail;
        err = lfs3_mount(&ctx->lfs3, 0, cfg);
        LLOGD("lfs3_mount after format %d", err);
        if (err)
            goto fail;
    }
    return &ctx->lfs3;

fail:
    luat_heap_free(ctx->rcache_buffer);
    luat_heap_free(ctx->pcache_buffer);
    luat_heap_free(ctx);
    return NULL;
}

#endif /* LUAT_USE_LFSV3_COMPONENT */
#endif /* LUAT_USE_FS_VFS */
#endif /* LUAT_USE_LITTLE_FLASH */
