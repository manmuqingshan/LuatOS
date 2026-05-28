#include "luat_base.h"
#include "pgfs_internal.h"
#include "luat_mem.h"
#include "luat_crypto.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#define PGFS_MAX_FILES 512
#define PGFS_DATA_RECORD_MAGIC 0x50474644u

typedef struct pgfs_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
} pgfs_data_record_hdr_t;

static pgfs_file_entry_t s_pgfs_files[PGFS_MAX_FILES];

static uint32_t pgfs_crc32_calc(const void* data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
}

static int pgfs_mode_is_write(const char* mode) {
    return mode && (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+'));
}

static int pgfs_mode_is_read(const char* mode) {
    return mode && (strchr(mode, 'r') || strchr(mode, '+'));
}

static int pgfs_path_copy(char* out, size_t outlen, const char* in) {
    size_t len = 0;
    if (out == NULL || outlen == 0 || in == NULL) {
        return -1;
    }
    len = strlen(in);
    if (len >= outlen) {
        return -1;
    }
    memcpy(out, in, len + 1);
    return 0;
}

static pgfs_file_entry_t* pgfs_find_file(const char* path) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (s_pgfs_files[i].used && strcmp(s_pgfs_files[i].path, path) == 0) {
            return &s_pgfs_files[i];
        }
    }
    return NULL;
}

static pgfs_file_entry_t* pgfs_alloc_file(const char* path) {
    size_t i = 0;
    pgfs_file_entry_t* e = pgfs_find_file(path);
    if (e) {
        return e;
    }
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (!s_pgfs_files[i].used) {
            memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
            s_pgfs_files[i].used = 1;
            if (pgfs_path_copy(s_pgfs_files[i].path, sizeof(s_pgfs_files[i].path), path) != 0) {
                memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
                return NULL;
            }
            return &s_pgfs_files[i];
        }
    }
    return NULL;
}

void pgfs_file_reset_all(void) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (s_pgfs_files[i].data) {
            luat_heap_free(s_pgfs_files[i].data);
        }
        memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
    }
}

int pgfs_file_remove(pgfs_mount_ctx_t* ctx, const char *filename) {
    pgfs_file_entry_t* e = NULL;
    (void)ctx;
    if (filename == NULL) {
        return -1;
    }
    e = pgfs_find_file(filename);
    if (e == NULL) {
        return -1;
    }
    if (e->data) {
        luat_heap_free(e->data);
    }
    memset(e, 0, sizeof(*e));
    return 0;
}

static int pgfs_file_reserve(pgfs_file_entry_t* e, size_t need) {
    size_t target = 0;
    uint8_t* p = NULL;
    if (e == NULL) {
        return -1;
    }
    if (need <= e->cap) {
        return 0;
    }
    target = e->cap == 0 ? 256 : e->cap;
    while (target < need) {
        size_t next = target << 1;
        if (next <= target) {
            return -1;
        }
        target = next;
    }
    p = (uint8_t*)luat_heap_realloc(e->data, target);
    if (!p) {
        return -1;
    }
    e->data = p;
    e->cap = target;
    return 0;
}

static int pgfs_append_data_record(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_data_record_hdr_t hdr = {0};
    uint8_t* crc_buf = NULL;
    size_t crc_len = 0;
    uint32_t addr = 0;
    if (ctx == NULL || f == NULL || f->entry == NULL || f->cache.len == 0 ||
        ctx->flash_opts == NULL || ctx->flash_opts->write == NULL) {
        return -1;
    }
    hdr.magic = PGFS_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)strlen(f->entry->path);
    hdr.data_len = (uint32_t)f->cache.len;
    crc_len = (size_t)hdr.path_len + f->cache.len;
    crc_buf = (uint8_t*)luat_heap_malloc(crc_len);
    if (crc_buf == NULL) {
        return -1;
    }
    memcpy(crc_buf, f->entry->path, hdr.path_len);
    memcpy(crc_buf + hdr.path_len, f->cache.data, f->cache.len);
    hdr.crc32 = pgfs_crc32_calc(crc_buf, crc_len);
    luat_heap_free(crc_buf);

    addr = ctx->data_log_write_addr;
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, (const uint8_t*)&hdr, sizeof(hdr)) != 0) {
        return -1;
    }
    addr += (uint32_t)sizeof(hdr);
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, (const uint8_t*)f->entry->path, hdr.path_len) != 0) {
        return -1;
    }
    addr += hdr.path_len;
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, f->cache.data, f->cache.len) != 0) {
        return -1;
    }
    ctx->data_log_write_addr = addr + (uint32_t)f->cache.len;
    return 0;
}

static int pgfs_apply_cache_to_entry(pgfs_file_t* f) {
    pgfs_file_entry_t* e = NULL;
    size_t old_len = 0;
    if (f == NULL || f->entry == NULL || f->cache.len == 0) {
        return 0;
    }
    e = f->entry;
    old_len = e->len;
    if (pgfs_file_reserve(e, f->cache.len) != 0) {
        return -1;
    }
    memcpy(e->data, f->cache.data, f->cache.len);
    e->len = f->cache.len;
    if (f->ctx) {
        f->ctx->checkpoint.gc_live_bytes += (uint32_t)f->cache.len;
        if (old_len > 0) {
            f->ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
        }
    }
    return 0;
}

FILE* pgfs_file_open(pgfs_mount_ctx_t* ctx, const char *filename, const char *mode) {
    pgfs_file_t* f = NULL;
    pgfs_file_entry_t* e = NULL;
    if (ctx == NULL || filename == NULL || mode == NULL) {
        return NULL;
    }
    if (pgfs_lock(ctx) != 0) {
        return NULL;
    }
    e = pgfs_mode_is_write(mode) ? pgfs_alloc_file(filename) : pgfs_find_file(filename);
    if (e == NULL) {
        pgfs_unlock(ctx);
        return NULL;
    }
    f = (pgfs_file_t*)luat_heap_malloc(sizeof(pgfs_file_t));
    if (f == NULL) {
        pgfs_unlock(ctx);
        return NULL;
    }
    memset(f, 0, sizeof(*f));
    f->ctx = ctx;
    f->entry = e;
    f->mode_write = (uint8_t)pgfs_mode_is_write(mode);
    f->mode_read = (uint8_t)pgfs_mode_is_read(mode);
    f->pos = 0;
    if (strchr(mode, 'a')) {
        f->pos = e->len;
    }
    pgfs_unlock(ctx);
    return (FILE*)f;
}

int pgfs_file_close(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    int ret = 0;
    uint32_t seg_id = 0;
    if (ctx == NULL || f == NULL) {
        return -1;
    }
    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    if (f->mode_write) {
        (void)pgfs_gc_step(ctx, 4096, 2000);
        (void)pgfs_alloc_segment(ctx, &seg_id);
        if (pgfs_cache_flush_to_log(ctx, f) != 0) {
            ret = -1;
            goto finish;
        }
        if (pgfs_append_data_record(ctx, f) != 0) {
            (void)pgfs_mark_block_retired(ctx, seg_id);
            ret = -1;
            goto finish;
        }
        if (pgfs_apply_cache_to_entry(f) != 0) {
            ret = -1;
            goto finish;
        }
        if (pgfs_checkpoint_store_next(ctx, &ctx->checkpoint, &ctx->checkpoint) != 0) {
            ret = -1;
            goto finish;
        }
        ctx->checkpoint_loaded = 1;
        ctx->checkpoint.used_blocks = (uint32_t)(ctx->checkpoint.used_blocks + 1u);
    }
finish:
    if (f->cache.data) {
        luat_heap_free(f->cache.data);
    }
    pgfs_unlock(ctx);
    luat_heap_free(f);
    return ret;
}

size_t pgfs_file_read(pgfs_mount_ctx_t* ctx, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t want = size * nmemb;
    size_t left = 0;
    size_t take = 0;
    (void)ctx;
    if (ptr == NULL || f == NULL || f->entry == NULL || !f->mode_read || size == 0 || nmemb == 0) {
        return 0;
    }
    if (f->pos >= f->entry->len) {
        f->eof = 1;
        return 0;
    }
    left = f->entry->len - f->pos;
    take = want < left ? want : left;
    memcpy(ptr, f->entry->data + f->pos, take);
    f->pos += take;
    f->eof = (f->pos >= f->entry->len) ? 1 : 0;
    return size == 0 ? 0 : (take / size);
}

size_t pgfs_file_write(pgfs_mount_ctx_t* ctx, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t total = size * nmemb;
    (void)ctx;
    if (f == NULL || ptr == NULL || !f->mode_write || size == 0 || nmemb == 0) {
        return 0;
    }
    if (pgfs_cache_append(f, (const uint8_t*)ptr, total) != 0) {
        return 0;
    }
    f->pos += total;
    return nmemb;
}

int pgfs_file_seek(pgfs_mount_ctx_t* ctx, FILE* stream, long int offset, int origin) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t base = 0;
    size_t npos = 0;
    (void)ctx;
    if (f == NULL || f->entry == NULL) {
        return -1;
    }
    if (origin == SEEK_SET) {
        base = 0;
    }
    else if (origin == SEEK_CUR) {
        base = f->pos;
    }
    else if (origin == SEEK_END) {
        base = f->entry->len;
    }
    else {
        return -1;
    }
    if (offset < 0 && (size_t)(-offset) > base) {
        return -1;
    }
    npos = offset < 0 ? (base - (size_t)(-offset)) : (base + (size_t)offset);
    if (npos > f->entry->len) {
        return -1;
    }
    f->pos = npos;
    f->eof = 0;
    return 0;
}

int pgfs_file_tell(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    if (f == NULL) {
        return -1;
    }
    return (int)f->pos;
}

int pgfs_file_eof(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    return f ? f->eof : 1;
}

int pgfs_file_error(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    return f ? f->err : 1;
}

int pgfs_file_flush(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    if (ctx == NULL || f == NULL) {
        return -1;
    }
    if (!f->mode_write) {
        return 0;
    }
    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    if (pgfs_cache_flush_to_log(ctx, f) != 0) {
        f->err = 1;
        pgfs_unlock(ctx);
        return -1;
    }
    pgfs_unlock(ctx);
    return 0;
}

#endif
    uint32_t seg_id = 0;
