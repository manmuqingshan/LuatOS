local ndk_tests = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024

local function assert_info_fields(info)
    local fields = {"mem", "exchange", "exchange_addr", "image", "running", "mcause", "mtval"}
    for _, key in ipairs(fields) do
        assert(info[key] ~= nil, "ndk.info missing field: " .. key)
    end
end

function ndk_tests.test_ndk_lifecycle_regression()
    assert(io.exists(IMAGE_PATH), "missing baremetal.bin in testcase directory: " .. IMAGE_PATH)

    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table")
    assert_info_fields(info)
    assert(info.mem == MEM_SIZE, "unexpected mem size: " .. tostring(info.mem))
    assert(info.exchange == EXCHANGE_SIZE, "unexpected exchange size: " .. tostring(info.exchange))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("ndk.exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(type(ret_or_err) == "number", "ndk.exec should return numeric retval")

    local idle_info = ndk.info(ctx)
    assert(type(idle_info) == "table", "ndk.info after exec should return table")
    assert(idle_info.running == false, "ndk must be idle before ndk.reset")

    local reset_ok, reset_err = ndk.reset(ctx)
    assert(reset_ok == true, "ndk.reset failed: " .. tostring(reset_err))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop no-op failed: " .. tostring(stop_err))

    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
end

return ndk_tests
