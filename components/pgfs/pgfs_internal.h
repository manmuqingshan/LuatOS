#ifndef PGFS_INTERNAL_H
#define PGFS_INTERNAL_H

#include "luat_pgfs.h"

typedef struct pgfs_mount_ctx {
    int mounted;
    char mount_point[16];
    pgfs_flash_opts_t flash_opts;
} pgfs_mount_ctx_t;

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void);

#endif
