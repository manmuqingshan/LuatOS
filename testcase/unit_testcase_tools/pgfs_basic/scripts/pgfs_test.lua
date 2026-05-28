local pgfs_tests = {}

local PGFS_SUPERBLOCK_A_ADDR = 0x0000
local PGFS_SUPERBLOCK_B_ADDR = 0x1000
local PGFS_CHECKPOINT_A_ADDR = 0x2000
local PGFS_CHECKPOINT_B_ADDR = 0x3000
local PGFS_ERASE_LEN = 0x4000

local PGFS_SB_MAGIC = 0x50474653
local PGFS_CP_MAGIC = 0x50474350
local PGFS_VERSION = 1
local s_spi_device = nil
local s_flash = nil
local s_mounted = false

local function setup_flash()
    if not s_spi_device then
        s_spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
        assert(s_spi_device, "spi.deviceSetup failed")
        s_flash = lf.init(s_spi_device)
        assert(s_flash, "lf.init failed")
    end
    assert(lf.erase(s_flash, 0, PGFS_ERASE_LEN), "lf.erase failed")
    sys.wait(30)
    assert(lf.pgfsctl("reset_runtime"), "pgfs reset_runtime failed")
    if not s_mounted then
        assert(lf.mount(s_flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
        s_mounted = true
    end
    return s_spi_device, s_flash
end

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

    local mounted = lf.mount(flash, "/pgfs_gen/", 0, 0, "pgfs")
    assert(mounted, "pgfs mount should fallback to valid generation")

    local ok, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/pgfs_gen/")
    assert(ok, "fs.fsstat(/pgfs/) failed")
    assert(fs_type == "pgfs", "expected pgfs fs type")
    assert(total_blocks == 128, "expected fallback generation total_blocks=128")
    assert(used_blocks == 11, "expected fallback generation used_blocks=11")
    assert(block_size > 0, "block_size should be positive")

end

function pgfs_tests.test_fclose_is_durable_boundary()
    setup_flash()

    local f = assert(io.open("/pgfs/durable.txt", "wb"))
    assert(f:write("commit_me"), "write failed")
    local before_close = io.readFile("/pgfs/durable.txt")
    assert(before_close ~= "commit_me", "data should not be durable before close")
    assert(f:close(), "close failed")

    local after_close = io.readFile("/pgfs/durable.txt")
    assert(after_close == "commit_me", "data must be durable after successful close")

end

function pgfs_tests.test_controlled_powercut_before_checkpoint()
    setup_flash()

    assert(lf.pgfsctl("powercut_stage", "before_checkpoint"), "set powercut_stage failed")
    local f = assert(io.open("/pgfs/powercut.txt", "wb"))
    assert(f:write("lost_on_powercut"), "write failed")
    local close_ok = f:close()
    assert(not close_ok, "close should fail under injected powercut")

    assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    assert(io.writeFile("/pgfs/powercut.txt", "recovered"), "rewrite failed")
    local data = io.readFile("/pgfs/powercut.txt")
    assert(data == "recovered", "data mismatch after clearing injection")

end

function pgfs_tests.test_control_invalid_args()
    setup_flash()
    assert(not lf.pgfsctl("lock_mode", "invalid"), "invalid lock_mode should fail")
    assert(not lf.pgfsctl("powercut_stage", "invalid"), "invalid powercut_stage should fail")
    assert(not lf.pgfsctl("unknown_cmd", true), "unknown pgfsctl command should fail")
end

function pgfs_tests.test_c_layer_selftests()
    setup_flash()
    assert(lf.pgfsctl("run_c_tests"), "pgfs C-layer selftests failed")
end

function pgfs_tests.test_info_fast_path_and_rebuild()
    local _, flash = setup_flash()

    assert(io.writeFile("/pgfs/info_probe.txt", "ok"), "write probe failed")
    sys.wait(30)
    local ok1, total1 = fs.fsstat("/pgfs/")
    assert(ok1, "first fsstat failed")
    assert(total1 and total1 > 0, "first fsstat total should be >0")

    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "erase metadata area failed")
    local ok2, total2 = fs.fsstat("/pgfs/")
    assert(ok2, "second fsstat should rebuild and pass")
    assert(total2 and total2 > 0, "second fsstat total should be >0")

end

function pgfs_tests.test_directory_listing_and_existence()
    setup_flash()

    local root_dir = "/pgfs/folder_vars"
    local nested_dir = root_dir .. "/vars"
    local nested_file = nested_dir .. "/config.txt"

    assert(io.mkdir(root_dir), "mkdir root_dir failed")
    assert(io.mkdir(nested_dir), "mkdir nested_dir failed")
    assert(io.writeFile(nested_file, "alpha"), "write nested_file failed")

    assert(io.dexist("/pgfs/"), "mount root should exist")
    assert(io.dexist(root_dir), "root_dir should exist")
    assert(io.dexist(nested_dir), "nested_dir should exist")
    assert(not io.dexist(root_dir .. "/missing"), "missing dir should not exist")
    assert(not io.dexist(nested_file), "file path should not be treated as directory")

    local ok_root, root_entries = io.lsdir("/pgfs/")
    assert(ok_root and type(root_entries) == "table", "lsdir /pgfs/ failed")
    local found_root = false
    for _, item in ipairs(root_entries) do
        if item.name == "folder_vars" and item.type == 1 then
            found_root = true
        end
    end
    assert(found_root, "root listing missing folder_vars")

    local ok_nested, nested_entries = io.lsdir(root_dir)
    assert(ok_nested and type(nested_entries) == "table", "lsdir root_dir failed")
    local found_nested = false
    for _, item in ipairs(nested_entries) do
        if item.name == "vars" and item.type == 1 then
            found_nested = true
        end
    end
    assert(found_nested, "nested listing missing vars")

    local ok_vars, vars_entries = io.lsdir(nested_dir)
    assert(ok_vars and type(vars_entries) == "table", "lsdir nested_dir failed")
    local found_file = false
    for _, item in ipairs(vars_entries) do
        if item.name == "config.txt" and item.type == 0 then
            found_file = true
        end
    end
    assert(found_file, "nested listing missing config.txt")

    assert(os.remove(nested_file), "remove nested file failed")
    assert(io.rmdir(nested_dir), "remove nested dir failed")
    assert(io.rmdir(root_dir), "remove root dir failed")
end

return pgfs_tests
