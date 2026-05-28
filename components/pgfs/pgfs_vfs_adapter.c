#include "luat_base.h"
#include <string.h>
#include "luat_pgfs.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#include "luat_fs.h"
#include "pgfs_internal.h"
#ifdef LUAT_USE_LITTLE_FLASH
#include "little_flash.h"
#endif

static pgfs_mount_ctx_t s_pgfs_ctx;

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void) {
    return &s_pgfs_ctx;
}

#ifdef LUAT_USE_LITTLE_FLASH
typedef struct {
    pgfs_flash_opts_t opts;
    little_flash_t* flash;
    uint32_t offset;
    uint32_t maxsize;
} pgfs_lf_bus_t;

static pgfs_lf_bus_t s_pgfs_lf_bus;

static int pgfs_lf_check_range(pgfs_lf_bus_t* bus, uint32_t addr, size_t len) {
    uint64_t end = 0;
    if (bus == NULL) {
        return -1;
    }
    end = (uint64_t)addr + (uint64_t)len;
    if (bus->maxsize != 0 && end > bus->maxsize) {
        return -1;
    }
    return 0;
}

static int pgfs_lf_read(void *ctx, uint32_t addr, uint8_t *buf, size_t len) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || buf == NULL || pgfs_lf_check_range(bus, addr, len) != 0) {
        return -1;
    }
    return little_flash_read(bus->flash, bus->offset + addr, buf, (uint32_t)len) == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_write(void *ctx, uint32_t addr, const uint8_t *buf, size_t len) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || buf == NULL || pgfs_lf_check_range(bus, addr, len) != 0) {
        return -1;
    }
    return little_flash_write(bus->flash, bus->offset + addr, buf, (uint32_t)len) == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_erase(void *ctx, uint32_t block_addr, uint32_t block_count) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || block_count == 0) {
        return -1;
    }
    return little_flash_erase(bus->flash, bus->offset + block_addr, block_count) == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_control(void *ctx, uint32_t cmd, void *arg) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    pgfs_flash_geometry_t* geo = (pgfs_flash_geometry_t*)arg;
    if (bus == NULL || bus->flash == NULL) {
        return -1;
    }
    if (cmd == PGFS_CTRL_GET_GEOMETRY && geo != NULL) {
        uint32_t cap = bus->flash->chip_info.capacity;
        if (cap > bus->offset) {
            cap -= bus->offset;
        }
        else {
            cap = 0;
        }
        if (bus->maxsize != 0 && cap > bus->maxsize) {
            cap = bus->maxsize;
        }
        geo->capacity = cap;
        geo->erase_size = bus->flash->chip_info.erase_size;
        geo->prog_size = bus->flash->chip_info.prog_size;
        return 0;
    }
    return -1;
}
#endif

static int luat_vfs_pgfs_mount(void** fsdata, luat_fs_conf_t *conf) {
    int ret = 0;
    size_t mlen = 0;
    if (fsdata == NULL || conf == NULL || conf->mount_point == NULL || conf->busname == NULL) {
        return -1;
    }
    memset(&s_pgfs_ctx, 0, sizeof(s_pgfs_ctx));
    pgfs_file_reset_all();
    mlen = strlen(conf->mount_point);
    if (mlen >= sizeof(s_pgfs_ctx.mount_point)) {
        mlen = sizeof(s_pgfs_ctx.mount_point) - 1;
    }
    memcpy(s_pgfs_ctx.mount_point, conf->mount_point, mlen);
    s_pgfs_ctx.mount_point[mlen] = 0;
    s_pgfs_ctx.flash_opts = (const pgfs_flash_opts_t *)conf->busname;
    s_pgfs_ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;

    ret = pgfs_checkpoint_load(&s_pgfs_ctx, &s_pgfs_ctx.checkpoint);
    if (ret != 0) {
        ret = pgfs_checkpoint_store_next(&s_pgfs_ctx, NULL, &s_pgfs_ctx.checkpoint);
        if (ret != 0) {
            memset(&s_pgfs_ctx, 0, sizeof(s_pgfs_ctx));
            return -1;
        }
    }
    s_pgfs_ctx.checkpoint_loaded = 1;
    s_pgfs_ctx.mounted = 1;
    *fsdata = &s_pgfs_ctx;
    return 0;
}

static int luat_vfs_pgfs_umount(void* fsdata, luat_fs_conf_t *conf) {
    (void)fsdata;
    (void)conf;
    memset(&s_pgfs_ctx, 0, sizeof(s_pgfs_ctx));
    return 0;
}

static int luat_vfs_pgfs_info(void* fsdata, const char* path, luat_fs_info_t *conf) {
    pgfs_mount_ctx_t* ctx = (pgfs_mount_ctx_t*)fsdata;
    (void)path;
    if (ctx == NULL || conf == NULL) {
        return -1;
    }
    return pgfs_info_fast(ctx, conf);
}

static int luat_vfs_pgfs_remove(void* fsdata, const char *filename) {
    return pgfs_file_remove((pgfs_mount_ctx_t*)fsdata, filename);
}

static FILE* luat_vfs_pgfs_fopen(void* fsdata, const char *filename, const char *mode) {
    return pgfs_file_open((pgfs_mount_ctx_t*)fsdata, filename, mode);
}

static int luat_vfs_pgfs_fclose(void* fsdata, FILE* stream) {
    return pgfs_file_close((pgfs_mount_ctx_t*)fsdata, stream);
}

static size_t luat_vfs_pgfs_fread(void* fsdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return pgfs_file_read((pgfs_mount_ctx_t*)fsdata, ptr, size, nmemb, stream);
}

static size_t luat_vfs_pgfs_fwrite(void* fsdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return pgfs_file_write((pgfs_mount_ctx_t*)fsdata, ptr, size, nmemb, stream);
}

static int luat_vfs_pgfs_fseek(void* fsdata, FILE* stream, long int offset, int origin) {
    return pgfs_file_seek((pgfs_mount_ctx_t*)fsdata, stream, offset, origin);
}

static int luat_vfs_pgfs_ftell(void* fsdata, FILE* stream) {
    return pgfs_file_tell((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_feof(void* fsdata, FILE* stream) {
    return pgfs_file_eof((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_ferror(void* fsdata, FILE *stream) {
    return pgfs_file_error((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_fflush(void* fsdata, FILE *stream) {
    return pgfs_file_flush((pgfs_mount_ctx_t*)fsdata, stream);
}

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = {
        .mount = luat_vfs_pgfs_mount,
        .umount = luat_vfs_pgfs_umount,
        .info = luat_vfs_pgfs_info,
        .remove = luat_vfs_pgfs_remove,
    },
    .fopts = {
        .fopen = luat_vfs_pgfs_fopen,
        .fseek = luat_vfs_pgfs_fseek,
        .ftell = luat_vfs_pgfs_ftell,
        .fclose = luat_vfs_pgfs_fclose,
        .feof = luat_vfs_pgfs_feof,
        .ferror = luat_vfs_pgfs_ferror,
        .fread = luat_vfs_pgfs_fread,
        .fwrite = luat_vfs_pgfs_fwrite,
        .fflush = luat_vfs_pgfs_fflush,
    },
};

void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize) {
#ifdef LUAT_USE_LITTLE_FLASH
    memset(&s_pgfs_lf_bus, 0, sizeof(s_pgfs_lf_bus));
    s_pgfs_lf_bus.flash = (little_flash_t*)flash;
    s_pgfs_lf_bus.offset = (uint32_t)offset;
    s_pgfs_lf_bus.maxsize = (uint32_t)maxsize;
    s_pgfs_lf_bus.opts.ctx = &s_pgfs_lf_bus;
    s_pgfs_lf_bus.opts.read = pgfs_lf_read;
    s_pgfs_lf_bus.opts.write = pgfs_lf_write;
    s_pgfs_lf_bus.opts.erase = pgfs_lf_erase;
    s_pgfs_lf_bus.opts.control = pgfs_lf_control;
    return &s_pgfs_lf_bus.opts;
#else
    (void)offset;
    (void)maxsize;
    return flash;
#endif
}

void pgfs_vfs_init(void) {
    static uint8_t inited = 0;
    if (!inited) {
        luat_pgfs_vfs_register();
        inited = 1;
    }
}

int luat_pgfs_vfs_register(void) {
    return luat_vfs_reg(&vfs_fs_pgfs);
}

int luat_pgfs_mount(const char *mount_point, const pgfs_flash_opts_t *opts) {
    luat_fs_conf_t conf = {
        .busname = (char*)opts,
        .type = "pgfs",
        .filesystem = "pgfs",
        .mount_point = mount_point,
    };
    return luat_fs_mount(&conf);
}

int luat_pgfs_umount(const char *mount_point) {
    luat_fs_conf_t conf = {
        .busname = NULL,
        .type = "pgfs",
        .filesystem = "pgfs",
        .mount_point = mount_point,
    };
    return luat_fs_umount(&conf);
}

int luat_pgfs_info(const char *path, luat_fs_info_t *info) {
    return luat_fs_info(path, info);
}

#else

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = {0},
    .fopts = {0},
};

void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize) {
    (void)flash;
    (void)offset;
    (void)maxsize;
    return NULL;
}

void pgfs_vfs_init(void) {
}

int luat_pgfs_vfs_register(void) {
    return -1;
}

int luat_pgfs_mount(const char *mount_point, const pgfs_flash_opts_t *opts) {
    (void)mount_point;
    (void)opts;
    return -1;
}

int luat_pgfs_umount(const char *mount_point) {
    (void)mount_point;
    return -1;
}

int luat_pgfs_info(const char *path, luat_fs_info_t *info) {
    (void)path;
    if (info != NULL) {
        memset(info, 0, sizeof(*info));
    }
    return -1;
}

#endif
