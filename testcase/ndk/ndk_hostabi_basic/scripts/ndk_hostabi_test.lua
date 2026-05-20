-- ndk_hostabi_test.lua
-- NDK host ABI fixture regression tests

local proto = require("hostabi_proto")

local tests = {}
local IMAGE = "/luadb/hostabi_v1.bin"

local function run_cmd(ctx, opcode, a0, a1, a2)
    local payload = proto.pack_cmd(opcode, a0, a1, a2)
    assert(ndk.reset(ctx))
    assert(ndk.setData(ctx, payload))
    local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    assert(ok == true, string.format("exec failed ret=%s mcause=%s mtval=%s", tostring(ret), tostring(mcause), tostring(mtval)))
    -- Result is at offset 16 (after the 16-byte command structure)
    return proto.unpack_result(assert(ndk.getData(ctx, proto.RESULT_SIZE, 16)))
end

function tests.test_guest_fixture_binary_present()
    assert(io.exists(IMAGE), "missing hostabi_v1.bin")
end

function tests.test_query_meta_command_reports_magic_and_version()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert(result.status == 0, "query meta should succeed")
    assert(result.value0 == proto.HOST_MAGIC, "unexpected magic")
    assert(result.value1 == proto.HOST_VERSION, "unexpected version")
end

return tests
