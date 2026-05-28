local pgfs_regression = {}
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
    assert(lf.erase(s_flash, 0, 0x4000), "lf.erase failed")
    if not s_mounted then
        assert(lf.mount(s_flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
        s_mounted = true
    end
    return s_spi_device, s_flash
end

function pgfs_regression.test_gc_under_churn()
    setup_flash()
    for i = 1, 200 do
        local name = "/pgfs/churn_" .. i .. ".txt"
        assert(io.writeFile(name, string.rep("X", 256)))
        if i % 3 == 0 then
            os.remove(name)
        end
    end
    local ok, total = fs.fsstat("/pgfs/")
    assert(ok, "fsstat failed")
    assert(total and total > 0, "invalid total")
end

function pgfs_regression.test_bad_block_retire_hook()
    setup_flash()
    assert(lf.pgfsctl("bad_block_once", true), "inject bad_block_once failed")
    io.writeFile("/pgfs/badblock_probe.txt", "first_maybe_fail")
    assert(io.writeFile("/pgfs/badblock_probe.txt", "ok"), "write failed after retire path")
    local data = io.readFile("/pgfs/badblock_probe.txt")
    assert(data == "ok", "badblock probe mismatch")
end

function pgfs_regression.test_lock_mode_toggle()
    setup_flash()
    assert(lf.pgfsctl("lock_mode", "on"), "set lock_mode on failed")
    assert(io.writeFile("/pgfs/lock_on.txt", "on"), "write with lock on failed")
    assert(lf.pgfsctl("lock_mode", "off"), "set lock_mode off failed")
    assert(io.writeFile("/pgfs/lock_off.txt", "off"), "write with lock off failed")
    assert(io.readFile("/pgfs/lock_on.txt") == "on", "lock on file mismatch")
    assert(io.readFile("/pgfs/lock_off.txt") == "off", "lock off file mismatch")
end

return pgfs_regression
