PROJECT = "pgfs_basic"
VERSION = "1.0.0"

sys = require("sys")

sys.taskInit(function()
    log.info("pgfs_basic", "setting up spi device")
    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")

    local flash = lf.init(spi_device)
    assert(flash, "lf.init returned nil")
    assert(lf.mount, "lf.mount is unavailable")

    local mounted = lf.mount(flash, "/pgfs/", 0, 0, "pgfs")
    assert(mounted, "lf.mount /pgfs failed")

    if spi_device.close then
        spi_device:close()
    end
    os.exit(0)
end)

sys.run()
