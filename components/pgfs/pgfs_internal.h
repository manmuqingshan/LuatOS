#ifndef PGFS_INTERNAL_H
#define PGFS_INTERNAL_H

#include "luat_pgfs.h"

#define PGFS_SUPERBLOCK_MAGIC        0x50474653u
#define PGFS_CHECKPOINT_MAGIC        0x50474350u
#define PGFS_ONDISK_VERSION          1u

#define PGFS_SUPERBLOCK_A_ADDR       0x0000u
#define PGFS_SUPERBLOCK_B_ADDR       0x1000u
#define PGFS_CHECKPOINT_A_ADDR       0x2000u
#define PGFS_CHECKPOINT_B_ADDR       0x3000u

#define PGFS_CTRL_GET_GEOMETRY       1u

#if defined(_MSC_VER)
#pragma pack(push, 1)
#endif

typedef struct pgfs_superblock {
    uint32_t magic;
    uint16_t version;
    uint16_t reserved;
    uint32_t seq;
    uint32_t checkpoint_addr;
    uint32_t checkpoint_len;
    uint32_t checkpoint_crc;
    uint32_t crc32;
}
#if !defined(_MSC_VER)
__attribute__((packed))
#endif
pgfs_superblock_t;

typedef struct pgfs_checkpoint {
    uint32_t magic;
    uint16_t version;
    uint16_t reserved;
    uint32_t seq;
    uint32_t total_blocks;
    uint32_t used_blocks;
    uint32_t flags;
    uint32_t crc32;
}
#if !defined(_MSC_VER)
__attribute__((packed))
#endif
pgfs_checkpoint_t;

typedef struct pgfs_flash_geometry {
    uint32_t capacity;
    uint32_t erase_size;
    uint32_t prog_size;
} pgfs_flash_geometry_t;

typedef struct pgfs_mount_ctx {
    int mounted;
    char mount_point[16];
    const pgfs_flash_opts_t *flash_opts;
    uint8_t checkpoint_loaded;
    uint8_t reserved[3];
    pgfs_checkpoint_t checkpoint;
} pgfs_mount_ctx_t;

#if defined(_MSC_VER)
#pragma pack(pop)
#endif

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void);

int pgfs_pick_latest_valid_sb(const pgfs_superblock_t* a, const pgfs_superblock_t* b, pgfs_superblock_t* out);
int pgfs_checkpoint_load(void* fs, pgfs_checkpoint_t* cp);
int pgfs_checkpoint_store_next(void* fs, const pgfs_checkpoint_t* current, pgfs_checkpoint_t* next);

#endif
