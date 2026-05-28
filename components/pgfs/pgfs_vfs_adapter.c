#include "luat_base.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#include <string.h>
#include "luat_fs.h"
#include "pgfs_internal.h"

static pgfs_mount_ctx_t s_pgfs_ctx;

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void) {
    return &s_pgfs_ctx;
}

static int luat_vfs_pgfs_mount(void** fsdata, luat_fs_conf_t *conf) {
    size_t mlen = 0;
    if (fsdata == NULL || conf == NULL || conf->mount_point == NULL) {
        return -1;
    }
    memset(&s_pgfs_ctx, 0, sizeof(s_pgfs_ctx));
    mlen = strlen(conf->mount_point);
    if (mlen >= sizeof(s_pgfs_ctx.mount_point)) {
        mlen = sizeof(s_pgfs_ctx.mount_point) - 1;
    }
    memcpy(s_pgfs_ctx.mount_point, conf->mount_point, mlen);
    s_pgfs_ctx.mount_point[mlen] = 0;
    if (conf->busname != NULL) {
        memcpy(&s_pgfs_ctx.flash_opts, conf->busname, sizeof(s_pgfs_ctx.flash_opts));
    }
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
    (void)fsdata;
    (void)path;
    if (conf == NULL) {
        return -1;
    }
    memset(conf, 0, sizeof(*conf));
    memcpy(conf->filesystem, "pgfs", strlen("pgfs") + 1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 4096;
    return 0;
}

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = {
        .mount = luat_vfs_pgfs_mount,
        .umount = luat_vfs_pgfs_umount,
        .info = luat_vfs_pgfs_info,
    },
    .fopts = {0},
};

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

#endif
