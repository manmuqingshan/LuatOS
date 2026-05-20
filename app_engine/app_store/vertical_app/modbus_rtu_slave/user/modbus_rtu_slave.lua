--[[
@module  modbus_rtu_slave
@summary RTU 从站应用模块
@version 1.0
@date    2026.05.18
@author  马梦阳
@usage
本模块实现 RTU 从站功能：
1、作为 Modbus RTU 从站响应主站请求
2、维护线圈、离散输入、保持寄存器、输入寄存器数据
3、通过事件机制与上层 UI 模块通信
]]

local modbus_rtu_slave = {}

-- ========================================
-- 模块级变量
-- ========================================

local exmodbus = require("exmodbus")

-- 任务名称（用于日志标识）
local TASK_NAME = "modbus_rtu_slave"

-- 实例字典（key=port_type, value=instance）
local instances = {}

-- 配置文件路径
local CONFIG_FILE = "/modbus_rtu_slave_config.json"

-- 默认配置参数
local DEFAULT_CONFIG = {
    uart_id = 1,
    baud_rate = 9600,
    data_bits = 8,
    stop_bits = 1,
    parity = "N",
    byte_order = 0,
    rs485_dir_gpio = 17,
    rs485_dir_rx_level = 0,
    rs485_vcc_gpio = -1,
    self_addr = 1,
    concat_timeout = 50,
}

-- ========================================
-- 校验位映射表（UI显示值 <-> exmodbus常量）
-- ========================================

local PARITY_MAP = {
    ["N"] = uart.None,
    ["E"] = uart.Even,
    ["O"] = uart.Odd,
}

--[[
将 UI 显示的校验位字符串转换为 exmodbus 常量
@local
@function parse_parity
@param parity_str string 校验位字符串 "N"/"E"/"O"
@return number exmodbus 校验位常量
]]
local function parse_parity(parity_str)
    return PARITY_MAP[parity_str] or uart.NONE
end

--=========================================
-- 寄存器注册表（地址 -> {name, value}）
--=========================================
local registered_registers = {}

--[[
@function modbus_rtu_slave.add_register
@summary 注册寄存器
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
]]
function modbus_rtu_slave.add_register(addr, name, value)
    registered_registers[addr] = {
        name = name,
        value = value or 0
    }
end

--[[
@function modbus_rtu_slave.remove_register
@summary 移除寄存器
@param addr number 寄存器地址
]]
function modbus_rtu_slave.remove_register(addr)
    registered_registers[addr] = nil
end

--[[
@function modbus_rtu_slave.get_register_value
@summary 获取寄存器值（读取时调用）
@param addr number 寄存器地址
@return number 寄存器值
]]
function modbus_rtu_slave.get_register_value(addr)
    local reg = registered_registers[addr]
    return reg and reg.value or 0
end

--[[
@function modbus_rtu_slave.set_register_value
@summary 设置寄存器值（写入时调用）
@param addr number 寄存器地址
@param value number 寄存器值
]]
function modbus_rtu_slave.set_register_value(addr, value)
    if registered_registers[addr] then
        registered_registers[addr].value = value
        sys.publish("modbus_register_update", {port_type = "rtu_slave", addr = addr, value = value})
    end
end

--[[
@function modbus_rtu_slave.format_hex_raw
@summary 格式化原始数据为十六进制字符串
@param data table|string 原始数据
@return string 格式化后的十六进制字符串
]]
function modbus_rtu_slave.format_hex_raw(data)
    if not data then
        return ""
    elseif data == "" then
        return ""
    elseif type(data) == "string" then
        local t = {}
        for i = 1, #data do
            t[i] = string.format("%02X", string.byte(data, i))
        end
        return table.concat(t, " ")
    elseif type(data) == "table" then
        local t = {}
        for i, v in ipairs(data) do
            t[i] = string.format("%02X", v)
        end
        return table.concat(t, " ")
    else
        return tostring(data)
    end
end

--[[
@function modbus_rtu_slave.get_config
@summary 获取配置
@return table 配置表
]]
function modbus_rtu_slave.get_config()
    if not io.exists(CONFIG_FILE) then
        log.info(TASK_NAME, "配置文件不存在，使用默认配置")
        return DEFAULT_CONFIG
    end

    local file = io.open(CONFIG_FILE, "r")
    if not file then
        log.error(TASK_NAME, "读取配置文件失败：无法打开文件")
        return DEFAULT_CONFIG
    end

    local content = file:read("*a")
    file:close()

    local config = json.decode(content)
    return config or DEFAULT_CONFIG
end

--[[
@function modbus_rtu_slave.save_config
@summary 保存配置（支持部分更新）
@param config table 配置表，支持完整配置或部分字段更新
@return boolean 是否保存成功
]]
function modbus_rtu_slave.save_config(config)
    local existing_config = modbus_rtu_slave.get_config()

    for key, value in pairs(config) do
        existing_config[key] = value
    end

    local file = io.open(CONFIG_FILE, "wb")
    if not file then
        log.error(TASK_NAME, "保存配置失败：无法打开文件")
        return false
    end

    local content = json.encode(existing_config)
    file:write(content)
    file:close()

    log.info(TASK_NAME, "配置已保存")
    return true
end

--[[
@function modbus_rtu_slave.start
@summary 启动RTU从站
@param port_type string 端口类型
@return boolean, string|nil 是否启动成功及错误原因
]]
function modbus_rtu_slave.start(port_type)
    if instances[port_type] then
        log.warn(TASK_NAME, "instance already exists", port_type)
        return false, "instance_already_exists"
    end

    local config = modbus_rtu_slave.get_config()

    log.info(TASK_NAME, "starting", "port=" .. port_type,
        "uart=" .. config.uart_id,
        "baud=" .. config.baud_rate,
        "parity=" .. config.parity,
        "addr=" .. config.self_addr)

    local rtu_config = {
        mode = exmodbus.RTU_SLAVE,
        uart_id = config.uart_id,
        baud_rate = config.baud_rate,
        data_bits = config.data_bits,
        stop_bits = config.stop_bits,
        parity_bits = parse_parity(config.parity),
        byte_order = config.byte_order or 0,
        rs485_dir_gpio = config.rs485_dir_gpio or 17,
        rs485_dir_rx_level = config.rs485_dir_rx_level or 0,
        concat_timeout = config.concat_timeout or 50,
    }

    local modbus = exmodbus.create(rtu_config)
    if not modbus then
        log.error(TASK_NAME, "exmodbus create failed")
        return false, "exmodbus_create_failed"
    end
    log.info(TASK_NAME, "exmodbus created successfully")

    -- 配置 485 芯片供电管脚为输出并拉高，使能 485 芯片供电
    -- 默认值 -1 表示不使用供电控制功能
    local vcc_gpio = config.rs485_vcc_gpio or -1
    if vcc_gpio >= 0 then
        gpio.setup(vcc_gpio, 1, gpio.PULLUP)
        log.info(TASK_NAME, "485芯片供电管脚已使能", "gpio=" .. vcc_gpio)
    end

    local self_addr = config.self_addr

    --[[
    @function build_request_frame
    @summary 内部函数：构建请求帧（用于日志打印）
    ]]
    local function build_request_frame(request)
        local frame = string.char(request.slave_id, request.func_code)
        if request.start_addr ~= nil then
            frame = frame .. string.char((request.start_addr >> 8) & 0xFF, request.start_addr & 0xFF)
        end
        if request.reg_count ~= nil then
            if request.reg_count == 1 and (request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER) then
                local val = request.data and request.data[request.start_addr] or 0
                frame = frame .. string.char((val >> 8) & 0xFF, val & 0xFF)
            else
                frame = frame .. string.char((request.reg_count >> 8) & 0xFF, request.reg_count & 0xFF)
            end
        end
        return frame
    end

    --[[
    @function build_response_frame
    @summary 内部函数：构建响应帧（用于日志打印）
    ]]
    local function build_response_frame(request, response_data)
        local func_code = request.func_code
        local frame = string.char(self_addr, func_code)

        if func_code == exmodbus.READ_COILS or func_code == exmodbus.READ_DISCRETE_INPUTS then
            local byte_count = math.ceil(request.reg_count / 8)
            frame = frame .. string.char(byte_count)
            for byte_idx = 0, byte_count - 1 do
                local byte_val = 0
                for bit_idx = 0, 7 do
                    local relative_addr = byte_idx * 8 + bit_idx
                    if relative_addr < request.reg_count then
                        local addr = request.start_addr + relative_addr
                        if response_data[addr] and response_data[addr] ~= 0 then
                            byte_val = byte_val | (1 << bit_idx)
                        end
                    end
                end
                frame = frame .. string.char(byte_val)
            end
        elseif func_code == exmodbus.READ_HOLDING_REGISTERS or func_code == exmodbus.READ_INPUT_REGISTERS then
            frame = frame .. string.char(request.reg_count * 2)
            for i = 0, request.reg_count - 1 do
                local addr = request.start_addr + i
                local val = response_data[addr] or 0
                frame = frame .. string.char((val >> 8) & 0xFF, val & 0xFF)
            end
        elseif func_code == exmodbus.WRITE_SINGLE_COIL or func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER then
            frame = frame .. string.char((request.start_addr >> 8) & 0xFF, request.start_addr & 0xFF)
            local val = request.data[request.start_addr] or 0
            frame = frame .. string.char((val >> 8) & 0xFF, val & 0xFF)
        elseif func_code == exmodbus.WRITE_MULTIPLE_COILS or func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
            frame = frame .. string.char((request.start_addr >> 8) & 0xFF, request.start_addr & 0xFF)
            frame = frame .. string.char((request.reg_count >> 8) & 0xFF, request.reg_count & 0xFF)
        end

        return frame
    end

    --[[
    @function publish_tx_log
    @summary 内部函数：发布TX日志
    ]]
    local function publish_tx_log(tx_frame)
        local tx_hex = modbus_rtu_slave.format_hex_raw(tx_frame)
        log.info(TASK_NAME, "TX", tx_hex)
        sys.publish("modbus_log", {port_type = "rtu_slave", message = "[TX] " .. tx_hex})
    end

    --[[
    @function callback
    @summary 主站请求处理回调函数
    ]]
    local function callback(request)
        -- 检查从站 ID 是否匹配
        if request.slave_id ~= self_addr then
            return nil
        end

        -- 打印接收到的请求帧
        local rx_frame = build_request_frame(request)
        local rx_hex = modbus_rtu_slave.format_hex_raw(rx_frame)
        log.info(TASK_NAME, "RX", rx_hex)
        sys.publish("modbus_log", {port_type = "rtu_slave", message = "[RX] " .. rx_hex})

        local is_write = false

        -- 判断是否为写操作
        if request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_MULTIPLE_COILS then
            is_write = true
        elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER or request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
            is_write = true
        elseif request.func_code == exmodbus.READ_COILS
            or request.func_code == exmodbus.READ_DISCRETE_INPUTS
            or request.func_code == exmodbus.READ_HOLDING_REGISTERS
            or request.func_code == exmodbus.READ_INPUT_REGISTERS then
            is_write = false
        else
            log.warn(TASK_NAME, "unsupported func_code", request.func_code)
            return exmodbus.ILLEGAL_FUNCTION
        end

        -- 处理读操作
        if not is_write then
            -- 根据功能码转换地址
            local base_addr = 1
            if request.func_code == exmodbus.READ_COILS then
                base_addr = 1  -- 线圈 00001-09999
            elseif request.func_code == exmodbus.READ_DISCRETE_INPUTS then
                base_addr = 10001  -- 离散输入 10001-19999
            elseif request.func_code == exmodbus.READ_HOLDING_REGISTERS then
                base_addr = 40001  -- 保持寄存器 40001-49999
            elseif request.func_code == exmodbus.READ_INPUT_REGISTERS then
                base_addr = 30001  -- 输入寄存器 30001-39999
            end

            -- 检查所有请求的地址是否都已注册
            for i = 0, request.reg_count - 1 do
                local absolute_addr = base_addr + request.start_addr + i
                if not registered_registers[absolute_addr] then
                    log.warn(TASK_NAME, "地址未注册", absolute_addr)
                    return exmodbus.ILLEGAL_DATA_ADDRESS
                end
            end

            -- 构建响应数据
            local response = {}
            for i = 0, request.reg_count - 1 do
                local relative_addr = request.start_addr + i
                local absolute_addr = base_addr + relative_addr
                response[relative_addr] = modbus_rtu_slave.get_register_value(absolute_addr)
            end
            log.info(TASK_NAME, "read success", "addr=" .. request.start_addr, "count=" .. request.reg_count)

            -- 发布TX响应帧日志
            local tx_frame = build_response_frame(request, response)
            publish_tx_log(tx_frame)

            -- 发布数据更新事件
            local event_data = {
                slave = self_addr,
                func_code = request.func_code,
                start_addr = request.start_addr,
                reg_count = request.reg_count,
                data = response,
            }
            sys.publish("modbus_data_update", {port_type = "rtu_slave", data = event_data})

            return response
        end

        -- 处理写操作
        if is_write then
            -- 根据功能码转换地址
            local base_addr = 1
            if request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_MULTIPLE_COILS then
                base_addr = 1  -- 线圈 00001-09999
            elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER or request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
                base_addr = 40001  -- 保持寄存器 40001-49999
            end

            -- 检查所有请求的地址是否都已注册
            for i = 0, request.reg_count - 1 do
                local absolute_addr = base_addr + request.start_addr + i
                if not registered_registers[absolute_addr] then
                    log.warn(TASK_NAME, "地址未注册", absolute_addr)
                    return exmodbus.ILLEGAL_DATA_ADDRESS
                end
            end

            -- 执行写入操作
            for i = 0, request.reg_count - 1 do
                local relative_addr = request.start_addr + i
                local absolute_addr = base_addr + relative_addr
                local value = request.data[relative_addr]
                modbus_rtu_slave.set_register_value(absolute_addr, value)
                log.info(TASK_NAME, "write success", "addr=" .. absolute_addr, "val=" .. value)
            end

            -- 发布TX响应帧日志
            local tx_frame = build_response_frame(request, {})
            publish_tx_log(tx_frame)

            -- 发布数据更新事件
            local event_data = {
                slave = self_addr,
                func_code = request.func_code,
                start_addr = request.start_addr,
                reg_count = request.reg_count,
                data = request.data,
            }
            sys.publish("modbus_data_update", {port_type = "rtu_slave", data = event_data})

            return {}
        end
    end

    modbus:on(callback)

    local instance = {
        modbus = modbus,
        rs485_vcc_gpio = vcc_gpio,
    }
    instances[port_type] = instance

    log.info(TASK_NAME, "RTU Slave running, addr=" .. config.self_addr)

    return true, nil
end

--[[
@function modbus_rtu_slave.stop
@summary 停止RTU从站
@param port_type string 端口类型
@return boolean, string|nil 是否停止成功及错误原因
]]
function modbus_rtu_slave.stop(port_type)
    local instance = instances[port_type]
    if not instance then
        log.warn(TASK_NAME, "instance not found", port_type)
        return false, "instance_not_found"
    end

    log.info(TASK_NAME, "stopping", port_type)

    -- 释放 485 芯片供电管脚
    if instance.rs485_vcc_gpio and instance.rs485_vcc_gpio >= 0 then
        gpio.close(instance.rs485_vcc_gpio)
        log.info(TASK_NAME, "485芯片供电管脚已释放", "gpio=" .. instance.rs485_vcc_gpio)
    end

    if instance.modbus then
        instance.modbus:destroy()
        instance.modbus = nil
    end

    instances[port_type] = nil
    log.info(TASK_NAME, "stopped", port_type)
    return true, nil
end

return modbus_rtu_slave
