local pgfs_regression = {}

local function setup_flash()
    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")
    local flash = lf.init(spi_device)
    assert(flash, "lf.init failed")
    assert(lf.erase(flash, 0, 0x4000), "lf.erase failed")
    assert(lf.mount(flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
    return spi_device, flash
end

function pgfs_regression.test_gc_under_churn()
    local spi_device = setup_flash()
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
    if spi_device.close then
        spi_device:close()
    end
end

function pgfs_regression.test_bad_block_retire_hook()
    local spi_device = setup_flash()
    assert(io.writeFile("/pgfs/badblock_probe.txt", "ok"), "write failed after retire path")
    local data = io.readFile("/pgfs/badblock_probe.txt")
    assert(data == "ok", "badblock probe mismatch")
    if spi_device.close then
        spi_device:close()
    end
end

return pgfs_regression
