
#include "luat_base.h"
#include "luat_luadb.h"
#include "luat_mem.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "luadb"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

#ifndef LUAT_CONF_LUADB_CUSTOM_READ
void luat_luadb_read_bytes(char* dst, const char* ptr, size_t len) {
    memcpy(dst, ptr, len);
}

static uint8_t readU8(const char* ptr, int *index) {
    int val = ptr[*index];
    *index = (*index) + 1;
    return val & 0xFF;
}

#else
extern void luat_luadb_read_bytes(char* dst, const char* ptr, size_t len);
static uint8_t readU8(const char* ptr, int *index) {
    char val = 0;
    luat_luadb_read_bytes(&val, ptr + (*index), 1);
    *index = (*index) + 1;
    return val & 0xFF;
}
#endif

static uint16_t readU16(const char* ptr, int *index) {
    return readU8(ptr,index) + (readU8(ptr,index) << 8);
}

static uint32_t readU32(const char* ptr, int *index) {
    return readU16(ptr,index) + (readU16(ptr,index) << 16);
}
//---


int luat_luadb_umount(luadb_fs_t *fs) {
    if (fs)
        luat_heap_free(fs);
    return 0;
}

int luat_luadb_remount(luadb_fs_t *fs, unsigned flags) {
    (void)flags;
    memset(fs->fds, 0, sizeof(luadb_fd_t)*LUAT_LUADB_MAX_OPENFILE);
    return 0;
}

static luadb_file_t* find_by_name(luadb_fs_t *fs, const char *path) {
    for (size_t i = 0; i < fs->filecount; i++)
    {
        if (!strcmp(path, fs->files[i].name)) {
            return &(fs->files[i]);
        }
    }
    // luadb_file_t *ext = fs->inlines;
    // while (ext->ptr != NULL)
    // {
    //     if (!strcmp(path, ext->name)) {
    //         return ext;
    //     }
    //     ext += 1;
    // }
    return NULL;
}

int luat_luadb_open(luadb_fs_t *fs, const char *path, int flags, int /*mode_t*/ mode) {
    (void)flags;
    (void)mode;
    LLOGD("open luadb path = %s flags=%d", path, flags);
    int fd = -1;
    for (size_t j = 1; j < LUAT_LUADB_MAX_OPENFILE; j++)
    {
        if (fs->fds[j].file == NULL) {
            fd = j;
            break;
        }
    }
    if (fd == -1) {
        LLOGD("too many open files for luadb");
        return 0;
    }
    luadb_file_t* f = find_by_name(fs, path);
    if (f != NULL) {
        fs->fds[fd].fd_pos = 0;
        fs->fds[fd].file = f;
        LLOGD("open luadb path = %s fd=%d", path, fd);
        return fd;
    }
    return 0;
}


int luat_luadb_close(luadb_fs_t *fs, int fd) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE)
        return -1;
    if (fs->fds[fd].file != NULL) {
        fs->fds[fd].file = NULL;
        fs->fds[fd].fd_pos = 0;
        return 0;
    }
    return -1;
}

size_t luat_luadb_read(luadb_fs_t *fs, int fd, void *dst, size_t size) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[fd].file == NULL)
        return 0;
    luadb_fd_t *fdt = &fs->fds[fd];
    int re = size;
    if (fdt->fd_pos >= fdt->file->size) {
        //LLOGD("luadb read name %s offset %d size %d ret 0", fdt->file->name, fdt->fd_pos, size);
        return 0; // 已经读完了
    }
    if (fdt->fd_pos + size > fdt->file->size) {
        re = fdt->file->size - fdt->fd_pos;
    }
    if (re > 0) {
        #ifndef LUAT_CONF_LUADB_CUSTOM_READ
        memcpy(dst, fdt->file->ptr + fdt->fd_pos, re);
        #else
        luat_luadb_read_bytes(dst, fdt->file->ptr + fdt->fd_pos, re);
        #endif
        fdt->fd_pos += re;
    }
    //LLOGD("luadb read name %s offset %d size %d ret %d", fdt->file->name, fdt->fd_pos, size, re);
    return re > 0 ? re : 0;
}

long luat_luadb_lseek(luadb_fs_t *fs, int fd, long /*off_t*/ offset, int mode) {
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[fd].file == NULL)
        return -1;
    if (mode == SEEK_END) {
        fs->fds[fd].fd_pos = fs->fds[fd].file->size - offset;
    }
    else if (mode == SEEK_CUR) {
        fs->fds[fd].fd_pos += offset;
    }
    else {
        fs->fds[fd].fd_pos = offset;
    }
    if (fs->fds[fd].fd_pos > fs->fds[fd].file->size) {
        fs->fds[fd].fd_pos = fs->fds[fd].file->size;
    }
    return fs->fds[fd].fd_pos;
}

luadb_file_t * luat_luadb_stat(luadb_fs_t *fs, const char *path) {
    return find_by_name(fs, path);
}

luadb_fs_t* luat_luadb_mount(const char* _ptr) {
    int index = 0;
    int headok = 0;
    int dbver = 0;
    int headsize = 0;
    size_t filecount = 0;

    const char * ptr = (const char *)_ptr;

    //LLOGD("LuaDB ptr = %p", ptr);
    uint16_t magic1 = 0;
    uint16_t magic2 = 0;

    for (size_t i = 0; i < 128; i++)
    {
        int type = readU8(ptr, &index);
        int len = readU8(ptr, &index);
        //LLOGD("PTR: %d %d %d", type, len, index);
        switch (type) {
            case 1: {// Magic, 肯定是4个字节
                if (len != 4) {
                    LLOGD("Magic len != 4");
                    goto _after_head;
                }
                magic1 = readU16(ptr, &index);
                magic2 = readU16(ptr, &index);
                if (magic1 != magic2 || magic1 != 0xA55A) {
                    LLOGD("Magic not match 0x%04X%04X", magic1, magic2);
                    goto _after_head;
                }
                break;
            }
            case 2: {
                if (len != 2) {
                    LLOGD("Version len != 2");
                    goto _after_head;
                }
                dbver = readU16(ptr, &index);
                LLOGD("LuaDB version = %d", dbver);
                break;
            }
            case 3: {
                if (len != 4) {
                    LLOGD("Header full len != 4");
                    goto _after_head;
                }
                headsize = readU32(ptr, &index);
                break;
            }
            case 4 : {
                if (len != 2) {
                    LLOGD("Lua File Count len != 4");
                    goto _after_head;
                }
                filecount = readU16(ptr, &index);
                LLOGD("LuaDB file count %d", filecount);
                break;
            }
            case 0xFE : {
                if (len != 2) {
                    LLOGD("CRC len != 4");
                    goto _after_head;
                }
                index += len;
                headok = 1;
                goto _after_head;
            }
            default: {
                index += len;
                LLOGD("skip unkown type %d", type);
                break;
            }
        }
    }

_after_head:

    if (headok == 0) {
        LLOGW("Bad LuaDB");
        return NULL;
    }
    if (dbver == 0) {
        LLOGW("miss DB version");
        return NULL;
    }
    if (headsize == 0) {
        LLOGW("miss DB headsize");
        return NULL;
    }
    if (filecount == 0) {
        LLOGW("miss DB filecount");
        return NULL;
    }
    if (filecount > 1024) {
        LLOGW("too many file in LuaDB");
        return NULL;
    }

    LLOGD("LuaDB head seem ok");

    // 由于luadb_fs_t带了一个luadb_file_t元素的
    size_t msize = sizeof(luadb_fs_t) + (filecount - 1)*sizeof(luadb_file_t);
    LLOGD("malloc fo luadb fs size=%d", msize);
    luadb_fs_t *fs = (luadb_fs_t*)luat_heap_malloc(msize);
    if (fs == NULL) {
        LLOGD("malloc for luadb fail!!!");
        return NULL;
    }
    memset(fs, 0, msize);
    LLOGD("LuaDB check files ....");

    fs->version = dbver;
    fs->filecount = filecount;
    //fs->ptrpos = initpos;

    int fail = 0;
    uint8_t type = 0;
    uint32_t len = 0;
    // int hasSys = 0;
    // 读取每个文件的头部
    for (size_t i = 0; i < filecount; i++)
    {
        
        LLOGD("LuaDB check files .... %d", i+1);
        
        type = readU8(ptr, &index);
        len = readU8(ptr, &index);
        if (type != 1 || len != 4) {
            LLOGD("bad file data 1 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // skip magic
        index += 4;

        // 2. 然后是名字
        type = readU8(ptr, &index);
        len = readU8(ptr, &index);
        if (type != 2) {
            LLOGD("bad file data 2 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // 拷贝文件名
        LLOGD("LuaDB file name len = %d", len);
        #ifndef LUAT_CONF_LUADB_CUSTOM_READ
        memcpy(fs->files[i].name, &(ptr[index]), len);
        #else
        luat_luadb_read_bytes(fs->files[i].name, ptr + index, len);
        #endif
        fs->files[i].name[len] = 0x00;
        index += len;

        LLOGD("LuaDB file name %.*s", len, fs->files[i].name);

        // 3. 文件大小
        type = readU8(ptr, &index);
        len = readU8(ptr, &index);
        if (type != 3 || len != 4) {
            LLOGD("bad file data 3 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        fs->files[i].size = readU32(ptr, &index);

        // 0xFE校验码
        type = readU8(ptr, &index);
        len = readU8(ptr, &index);
        if (type != 0xFE || len != 2) {
            LLOGD("bad file data 4 : %d %d %d", type, len, index);
            fail = 1;
            break;
        }
        // 校验码就跳过吧
        index += len;
        
        fs->files[i].ptr = (const char*)(index + ptr); // 绝对地址
        index += fs->files[i].size;

        LLOGD("LuaDB: %s %d", fs->files[i].name, fs->files[i].size);
    }

    if (fail == 0) {
        LLOGD("LuaDB check files .... ok");
        // #ifdef LUAT_CONF_VM_64bit
        // //#if (sizeof(size_t) == 8)
        // //fs->inlines = (luadb_file_t *)luat_inline2_libs_64bit_size64;
        // //#else
        // fs->inlines = (luadb_file_t *)luat_inline2_libs_64bit_size32;
        // //#endif
        // #else
        // fs->inlines = (luadb_file_t *)luat_inline2_libs;
        // #endif
        return fs;
    }
    else {
        LLOGD("LuaDB check files .... fail");
        luat_heap_free(fs);
        return NULL;
    }
}

#ifdef LUAT_USE_FS_VFS

FILE* luat_vfs_luadb_fopen(void* userdata, const char *filename, const char *mode) {
    if (!strcmp("r", mode) || !strcmp("rb", mode) || !strcmp("r+", mode) || !strcmp("rb+", mode)) {
    }
    else {
        LLOGW("/luadb is readonly %s %s", filename, mode);
        return (FILE*)NULL;
    }
    return (FILE*)luat_luadb_open((luadb_fs_t*)userdata, filename, 0, 0);
}


int luat_vfs_luadb_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    int ret = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, offset, origin);
    if (ret < 0)
        return -1;
    return 0;
}

int luat_vfs_luadb_ftell(void* userdata, FILE* stream) {
    return luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_CUR);
}

int luat_vfs_luadb_fclose(void* userdata, FILE* stream) {
    return luat_luadb_close((luadb_fs_t*)userdata, (int)stream);
}
int luat_vfs_luadb_feof(void* userdata, FILE* stream) {
    int cur = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_CUR);
    int end = luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, 0, SEEK_END);
    luat_luadb_lseek((luadb_fs_t*)userdata, (int)stream, cur, SEEK_SET);
    return cur >= end ? 1 : 0;
}
int luat_vfs_luadb_ferror(void* userdata, FILE *stream) {
    (void)userdata;
    (void)stream;
    return 0;
}
size_t luat_vfs_luadb_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return luat_luadb_read((luadb_fs_t*)userdata, (int)stream, ptr, size * nmemb);
}

int luat_vfs_luadb_getc(void* userdata, FILE* stream) {
    char c = 0;
    size_t ret = luat_vfs_luadb_fread((luadb_fs_t*)userdata, &c, 1, 1, stream);
    if (ret > 0) {
        return (int)c;
    }
    return -1;
}
size_t luat_vfs_luadb_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    (void)stream;
    (void)ptr;
    (void)size;
    (void)nmemb;
    return 0;
}
int luat_vfs_luadb_remove(void* userdata, const char *filename) {
    (void)userdata;
    (void)filename;
    LLOGW("/luadb is readonly %s", filename);
    return -1;
}
int luat_vfs_luadb_rename(void* userdata, const char *old_filename, const char *new_filename) {
    (void)userdata;
    (void)old_filename;
    (void)new_filename;
    LLOGW("/luadb is readonly %s", old_filename);
    return -1;
}
int luat_vfs_luadb_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_luadb_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_luadb_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_luadb_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_luadb_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_luadb_fseek(userdata, fd, 0, SEEK_END);
        size = luat_vfs_luadb_ftell(userdata, fd); 
        luat_vfs_luadb_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_luadb_mkfs(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : mkfs");
    (void)userdata;
    (void)conf;
    return -1;
}
int luat_vfs_luadb_mount(void** userdata, luat_fs_conf_t *conf) {
    luadb_fs_t* fs = luat_luadb_mount((const char*)conf->busname);
    if (fs == NULL)
        return  -1;
    *userdata = fs;
    return 0;
}
int luat_vfs_luadb_umount(void* userdata, luat_fs_conf_t *conf) {
    //LLOGE("not support yet : umount");
    (void)userdata;
    (void)conf;
    return 0;
}

int luat_vfs_luadb_mkdir(void* userdata, char const* _DirName) {
    //LLOGE("not support yet : mkdir");
    (void)userdata;
    (void)_DirName;
    return -1;
}

int luat_vfs_luadb_rmdir(void* userdata, char const* _DirName) {
    //LLOGE("not support yet : rmdir");
    (void)userdata;
    (void)_DirName;
    return -1;
}

int luat_vfs_luadb_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    (void)_DirName;
    luadb_fs_t* fs = (luadb_fs_t*)userdata;
    if (fs->filecount > offset) {
        if (offset + len > fs->filecount)
            len = fs->filecount - offset;
        for (size_t i = 0; i < len; i++)
        {
            ents[i].d_type = 0;
            strcpy(ents[i].d_name, fs->files[i+offset].name);
        }
        return len;
    }
    return 0;
}

// 这个全局变量是给bsp自行设置的,名字不要动
size_t luat_luadb_act_size;

int luat_vfs_luadb_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    (void)path;
    memcpy(conf->filesystem, "luadb", strlen("luadb")+1);
    // 把luadb的第一个文件的偏移量估算为起始位置
    // 最后一个文件的偏移量+文件大小, 作为结束位置
    // 从而估算出luadb的实际用量
    size_t used = 0;
    luadb_fs_t* fs = (luadb_fs_t*)userdata;
    if (fs != NULL && fs->filecount > 0) {
        size_t begin = (size_t)fs->files[0].ptr;
        size_t end = (size_t)(fs->files[fs->filecount - 1].ptr) +  fs->files[fs->filecount - 1].size;
        used = end - begin + 512;
    }
    conf->type = 0;
    conf->total_block = luat_luadb_act_size / 512;
    conf->block_used = (used / 512) + 1;
    conf->block_size = 512;
    return 0;
}

void* luat_vfs_luadb_mmap(void* userdata, FILE* f) {
    luadb_fs_t* fs = (luadb_fs_t*)userdata;
    int fd = (int)f;
    if (fd < 0 || fd >= LUAT_LUADB_MAX_OPENFILE || fs->fds[(int)fd].file == NULL)
        return 0;
    luadb_fd_t *fdt = &fs->fds[(int)fd];
    if (fdt != NULL) {
        return (void*)fdt->file->ptr;
    }
    return NULL;
}

#define T(name) .name = luat_vfs_luadb_##name
const struct luat_vfs_filesystem vfs_fs_luadb = {
    .name = "luadb",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        .mkdir = NULL,
        .rmdir = NULL,
        T(lsdir),
        .remove = NULL,
        .rename = NULL,
        T(fsize),
        T(fexist),
        T(info)
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
    #ifndef LUAT_CONF_LUADB_CUSTOM_READ
        T(mmap),
    #endif
        .fwrite = NULL
    }
};
#endif
