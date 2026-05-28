#ifndef LUAT_PGFS_H
#define LUAT_PGFS_H

#include <stddef.h>
#include <stdint.h>
#include "luat_fs.h"

typedef struct pgfs_flash_opts {
    void *ctx;
    int (*read)(void *ctx, uint32_t addr, uint8_t *buf, size_t len);
    int (*write)(void *ctx, uint32_t addr, const uint8_t *buf, size_t len);
    int (*erase)(void *ctx, uint32_t block_addr, uint32_t block_count);
    int (*control)(void *ctx, uint32_t cmd, void *arg);
} pgfs_flash_opts_t;

extern const struct luat_vfs_filesystem vfs_fs_pgfs;

void pgfs_vfs_init(void);
void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize);
int luat_pgfs_vfs_register(void);
int luat_pgfs_mount(const char *mount_point, const pgfs_flash_opts_t *opts);
int luat_pgfs_umount(const char *mount_point);
int luat_pgfs_info(const char *path, luat_fs_info_t *info);

#endif
