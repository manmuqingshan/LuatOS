-- hostabi_proto.lua
-- Protocol definitions for NDK host ABI testing

local M = {}

-- Command opcodes
M.CMD_QUERY_META = 0x01
M.CMD_DELAY_US = 0x02
M.CMD_EVENT_STATE = 0x03

-- Protocol constants
M.HOST_MAGIC = 0x4E444B31  -- "NDK1"
M.HOST_VERSION = 0x00010000  -- 1.0.0
M.RESULT_SIZE = 16

-- Pack command structure (opcode, arg0, arg1, arg2)
function M.pack_cmd(opcode, a0, a1, a2)
    return string.pack("<I4I4I4I4", opcode, a0 or 0, a1 or 0, a2 or 0)
end

-- Unpack result structure (status, value0, value1, value2)
function M.unpack_result(data)
    if not data or #data < M.RESULT_SIZE then
        return {status = 255, value0 = 0, value1 = 0, value2 = 0}
    end
    local status, v0, v1, v2 = string.unpack("<I4I4I4I4", data)
    return {status = status, value0 = v0, value1 = v1, value2 = v2}
end

return M
