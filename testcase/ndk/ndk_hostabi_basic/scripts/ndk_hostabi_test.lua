-- ndk_hostabi_test.lua
-- NDK host ABI fixture regression tests

local proto = require("hostabi_proto")

local tests = {}
local IMAGE = "/luadb/hostabi_v1.bin"

local function run_cmd(ctx, opcode, a0, a1, a2)
    return run_cmd_with_reset(ctx, opcode, a0, a1, a2, true)
end

function run_cmd_with_reset(ctx, opcode, a0, a1, a2, do_reset)
    local payload = proto.pack_cmd(opcode, a0, a1, a2)
    if do_reset ~= false then
        assert(ndk.reset(ctx))
    end
    assert(ndk.setData(ctx, payload))
    local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    assert(ok == true, string.format("exec failed ret=%s mcause=%s mtval=%s", tostring(ret), tostring(mcause), tostring(mtval)))
    return proto.unpack_result(assert(ndk.getData(ctx, proto.RESULT_SIZE, proto.RESULT_OFFSET)))
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

function tests.test_ndk_info_exposes_abi_fields()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local info = ndk.info(ctx)
    assert(info.abi_magic == proto.HOST_MAGIC, "missing abi_magic")
    assert(info.abi_version == proto.HOST_VERSION, "missing abi_version")
    assert(type(info.features) == "number", "missing features")
    assert(info.last_error == 0, "missing last_error")
    assert(info.event_slots >= 1, "missing event_slots")
end

function tests.test_delay_command_succeeds_and_returns_timestamp()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 1000  -- Request 1ms delay
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value0 > 0, "timestamp should be non-zero")
end

function tests.test_delay_command_reports_pending_event_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 500
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value1 == 1, "pending flag should be 1 after delay")
end

function tests.test_event_state_command_reports_pending_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local state = run_cmd(ctx, proto.CMD_EVENT_STATE, 0, 0, 0)
    assert(state.status == 0, "event state command should succeed")
    assert(state.value0 == 0, "fresh context should report no pending event")
end

function tests.test_event_header_reflects_timer_event()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 1000
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    -- Read entire exchange buffer to inspect event header
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local header = proto.unpack_event_header(exchange_data)
    assert(header.host_write == 1, "host_write should be 1")
    assert(header.guest_read == 0, "guest_read should be 0")
    assert(header.slot_count == 8, "slot_count should match configured event slots")
    assert(header.overflow == 0, "overflow should be 0")
end

function tests.test_first_event_slot_contains_timer_event()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 2000
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    -- Read event slot
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local event = proto.unpack_event_slot(exchange_data, 0)
    assert(event.type == proto.EVENT_TYPE_TIMER, "event type should be TIMER")
    assert(event.data == delay_us, "event data should match requested delay")
end

function tests.test_gpio_config_command_succeeds()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_GPIO_CONFIG, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT)
    assert(result.status == proto.STATUS_OK, "gpio config should succeed")
end

function tests.test_gpio_write_then_read_round_trip()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_cmd(ctx, proto.CMD_GPIO_CONFIG, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT)
    assert(cfg.status == proto.STATUS_OK, "gpio config should succeed")
    local wr = run_cmd_with_reset(ctx, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "gpio write should succeed")
    local rd = run_cmd_with_reset(ctx, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(rd.status == proto.STATUS_OK, "gpio read should succeed")
    assert(rd.value0 == 1, "gpio read should report written level")
end

function tests.test_gpio_irq_state_reports_pending_after_trigger()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_cmd(ctx, proto.CMD_GPIO_CONFIG, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local state = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_STATE, 9, 0, 0, false)
    assert(state.status == proto.STATUS_OK, "gpio irq state should succeed")
    assert(state.value0 == 1, "gpio irq should be pending after simulator trigger")
end

function tests.test_gpio_irq_clear_removes_pending_state()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_cmd(ctx, proto.CMD_GPIO_CONFIG, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local clr = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_CLEAR, 9, 0, 0, false)
    assert(clr.status == proto.STATUS_OK, "gpio irq clear should succeed")
    local state = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_STATE, 9, 0, 0, false)
    assert(state.value0 == 0, "gpio irq clear should drop pending state")
end

function tests.test_gpio_irq_event_appears_in_event_ring()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_cmd(ctx, proto.CMD_GPIO_CONFIG, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local event = proto.unpack_event_slot(exchange_data, 0)
    assert(event.type == proto.EVENT_TYPE_GPIO_IRQ, "event type should be GPIO_IRQ")
    assert(event.data ~= 0, "gpio irq event payload should be non-zero")
end

return tests
