local pgfs_tests = {}

local PGFS_SUPERBLOCK_A_ADDR = 0x0000
local PGFS_SUPERBLOCK_B_ADDR = 0x1000
local PGFS_CHECKPOINT_A_ADDR = 0x2000
local PGFS_CHECKPOINT_B_ADDR = 0x3000
local PGFS_ERASE_LEN = 0x4000

local PGFS_SB_MAGIC = 0x50474653
local PGFS_CP_MAGIC = 0x50474350
local PGFS_VERSION = 1

local function crc32_raw(data)
    return crypto.crc32(data, 0xFFFFFFFF, 0x04C11DB7, 0) & 0xFFFFFFFF
end

local function build_checkpoint(seq, total_blocks, used_blocks)
    local body_with_zero_crc = string.pack("<I4I2I2I4I4I4I4I4I4I4",
        PGFS_CP_MAGIC,
        PGFS_VERSION,
        0,
        seq,
        total_blocks,
        used_blocks,
        0,
        0,
        0,
        0)
    local crc = crc32_raw(body_with_zero_crc)
    return body_with_zero_crc:sub(1, -5) .. string.pack("<I4", crc), crc
end

local function build_superblock(seq, cp_addr, cp_len, cp_crc)
    local body_with_zero_crc = string.pack("<I4I2I2I4I4I4I4I4",
        PGFS_SB_MAGIC,
        PGFS_VERSION,
        0,
        seq,
        cp_addr,
        cp_len,
        cp_crc,
        0)
    local crc = crc32_raw(body_with_zero_crc)
    return body_with_zero_crc:sub(1, -5) .. string.pack("<I4", crc)
end

function pgfs_tests.test_generation_fallback_prefers_latest_valid()
    assert(string.pack, "string.pack is unavailable")
    assert(crypto and crypto.crc32, "crypto.crc32 is unavailable")

    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")

    local flash = lf.init(spi_device)
    assert(flash, "lf.init failed")

    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "lf.erase failed")

    local cp_a, cp_a_crc = build_checkpoint(1, 128, 11)
    local cp_b, cp_b_crc = build_checkpoint(2, 128, 22)
    local sb_a = build_superblock(1, PGFS_CHECKPOINT_A_ADDR, #cp_a, cp_a_crc)
    local sb_b = build_superblock(2, PGFS_CHECKPOINT_B_ADDR, #cp_b, cp_b_crc)

    local sb_b_corrupt = sb_b:sub(1, -2) .. string.char((sb_b:byte(-1) ~ 0xFF) & 0xFF)

    assert(lf.write(flash, PGFS_CHECKPOINT_A_ADDR, cp_a), "write cp_a failed")
    assert(lf.write(flash, PGFS_CHECKPOINT_B_ADDR, cp_b), "write cp_b failed")
    assert(lf.write(flash, PGFS_SUPERBLOCK_A_ADDR, sb_a), "write sb_a failed")
    assert(lf.write(flash, PGFS_SUPERBLOCK_B_ADDR, sb_b_corrupt), "write sb_b failed")

    local mounted = lf.mount(flash, "/pgfs/", 0, 0, "pgfs")
    assert(mounted, "pgfs mount should fallback to valid generation")

    local ok, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/pgfs/")
    assert(ok, "fs.fsstat(/pgfs/) failed")
    assert(fs_type == "pgfs", "expected pgfs fs type")
    assert(total_blocks == 128, "expected fallback generation total_blocks=128")
    assert(used_blocks == 11, "expected fallback generation used_blocks=11")
    assert(block_size > 0, "block_size should be positive")

    if spi_device.close then
        spi_device:close()
    end
end

function pgfs_tests.test_fclose_is_durable_boundary()
    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")

    local flash = lf.init(spi_device)
    assert(flash, "lf.init failed")

    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "lf.erase failed")
    assert(lf.mount(flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")

    local f = assert(io.open("/pgfs/durable.txt", "wb"))
    assert(f:write("commit_me"), "write failed")
    local before_close = io.readFile("/pgfs/durable.txt")
    assert(before_close ~= "commit_me", "data should not be durable before close")
    assert(f:close(), "close failed")

    local after_close = io.readFile("/pgfs/durable.txt")
    assert(after_close == "commit_me", "data must be durable after successful close")

    if spi_device.close then
        spi_device:close()
    end
end

function pgfs_tests.test_info_fast_path_and_rebuild()
    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")

    local flash = lf.init(spi_device)
    assert(flash, "lf.init failed")
    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "lf.erase failed")
    assert(lf.mount(flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")

    assert(io.writeFile("/pgfs/info_probe.txt", "ok"), "write probe failed")
    local ok1, total1 = fs.fsstat("/pgfs/")
    assert(ok1, "first fsstat failed")
    assert(total1 and total1 > 0, "first fsstat total should be >0")

    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "erase metadata area failed")
    local ok2, total2 = fs.fsstat("/pgfs/")
    assert(ok2, "second fsstat should rebuild and pass")
    assert(total2 and total2 > 0, "second fsstat total should be >0")

    if spi_device.close then
        spi_device:close()
    end
end

return pgfs_tests
