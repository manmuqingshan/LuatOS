sys.taskInit(function()
    sys.wait(100)
    local ctx, err = ndk.rv32i("/luadb/baremetal.bin", 32 * 1024, 1024)
    if not ctx then
        log.error("ndk", err)
        os.exit(1)
        return
    end
    local info = ndk.info(ctx)
    log.info("ndk", "mem", info.mem, "exchange", info.exchange, "running", info.running)

    local wrote = ndk.setData(ctx, "hello ndk")
    log.info("ndk", "setData", wrote)

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    if not ok then
        log.error("ndk", "exec", ret_or_err, "mcause", mcause, "mtval", mtval)
        ndk.stop(ctx, 1000)
        os.exit(1)
        return
    end
    log.info("ndk", "retval", ret_or_err)

    local data = ndk.getData(ctx, 16, 0)
    log.info("ndk", "getData", data)

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    log.info("ndk", "stop", stop_ok, stop_err)

    local reset_ok, reset_err = ndk.reset(ctx)
    log.info("ndk", "reset", reset_ok, reset_err)

    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
    os.exit(0)
end)

sys.run()
