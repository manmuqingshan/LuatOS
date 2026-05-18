--[[
@module  modbus_rtu_master
@summary RTU 主站应用模块
@version 1.0
@date    2026.05.13
@author  马梦阳
@usage
本模块实现 RTU 主站功能：
1、作为 Modbus RTU 主站向从站发起读写请求
2、支持标准功能码 0x01/02/03/04/05/06/0F/10
3、通过事件机制与上层 UI 模块通信
]]

local modbus_rtu_master = {}

-- ========================================
-- 模块级变量
-- ========================================

-- exmodbus 主模块引用
local exmodbus = require("exmodbus")

-- 任务名称（用于日志标识）
local TASK_NAME = "modbus_rtu_master"

-- 实例字典（key=port_type, value=instance）
local instances = {}

-- 配置文件路径
local CONFIG_FILE = "/modbus_rtu_master_config.json"

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
    slave_id = 1,
    poll_interval = 1000,
    timeout = 3000
}

-- ========================================
-- 校验位映射表（UI显示值 <-> exmodbus常量）
-- ========================================

local PARITY_MAP = {
    ["N"] = uart.None,
    ["E"] = uart.Even,
    ["O"] = uart.Odd,
}
local PARITY_REVERSE_MAP = {}
for k, v in pairs(PARITY_MAP) do
    PARITY_REVERSE_MAP[v] = k
end

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

--[[
将 exmodbus 校验位常量转换为 UI 显示字符串
@local
@function format_parity
@param parity_val number exmodbus 校验位常量
@return string 校验位字符串
]]
local function format_parity(parity_val)
    return PARITY_REVERSE_MAP[parity_val] or "N"
end

-- ========================================
-- 寄存器注册表
-- ========================================

local registered_registers = {}

--[[
将逻辑地址转换为 Modbus 物理地址和寄存器类型
@local
@function logical_to_physical
@param addr number 逻辑地址（1-9999, 10001-19999, 30001-39999, 40001-49999）
@return number, number|nil 成功返回物理地址和寄存器类型，失败返回 nil
]]
local function logical_to_physical(addr)
    if addr >= 1 and addr <= 9999 then
        return addr - 1, exmodbus.COIL_STATUS
    elseif addr >= 10001 and addr <= 19999 then
        return addr - 10001, exmodbus.INPUT_STATUS
    elseif addr >= 30001 and addr <= 39999 then
        return addr - 30001, exmodbus.INPUT_REGISTER
    elseif addr >= 40001 and addr <= 49999 then
        return addr - 40001, exmodbus.HOLDING_REGISTER
    else
        return nil
    end
end

--[[
将二进制数据转换为十六进制字符串
@local
@function format_hex
@param data string|number[] 二进制数据或数字数组
@return string 十六进制字符串
]]
local function format_hex(data)
    if type(data) == "string" then
        local hex = ""
        for i = 1, #data do
            hex = hex .. string.format("%02X ", string.byte(data, i))
        end
        return hex:sub(1, -2)
    else
        local hex = ""
        for i = 1, #data do
            hex = hex .. string.format("%02X ", data[i])
        end
        return hex:sub(1, -2)
    end
end

--[[
@function modbus_rtu_master.add_register
@summary 注册需要轮询的寄存器地址
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
@param rw string 读写属性，"r"=只读，"w"=只写，默认"r"
]]
function modbus_rtu_master.add_register(addr, name, value, rw)
    registered_registers[addr] = {
        name = name,
        value = value or 0,
        rw = rw or "r"
    }
end

--[[
@function modbus_rtu_master.remove_register
@summary 移除已注册的寄存器地址
@param addr number 寄存器地址
]]
function modbus_rtu_master.remove_register(addr)
    registered_registers[addr] = nil
end

-- ========================================
-- 轮询任务
-- ========================================

local function polling_once(port_type)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        return
    end

    local config = modbus_rtu_master.get_config()
    local slave_id = config.slave_id or 1
    local timeout = config.timeout

    local update_data = {}

    log.info(TASK_NAME, "当前轮询配置:", slave_id, timeout)

    for addr, reg_info in pairs(registered_registers) do
        local physical_addr, reg_type = logical_to_physical(addr)
        if not physical_addr then
            sys.publish("modbus_log", {
                port_type = port_type,
                message = "地址[" .. addr .. "]超出范围"
            })
        elseif reg_info.rw == "w" then
            local write_config = {
                slave_id = slave_id,
                reg_type = reg_type,
                start_addr = physical_addr,
                reg_count = 1,
                data = { [physical_addr] = reg_info.value },
                timeout = timeout
            }

            local result = instance.modbus:write(write_config)

            if result.raw_request then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "[TX] " .. format_hex(result.raw_request)
                })
            end

            if result.raw_response then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "[RX] " .. format_hex(result.raw_response)
                })
            end

            if result.status ~= exmodbus.STATUS_SUCCESS then
                if result.status == exmodbus.STATUS_DATA_INVALID then
                    sys.publish("modbus_log", {
                        port_type = port_type,
                        message = "写[地址" .. addr .. "]数据损坏/校验失败"
                    })
                elseif result.status == exmodbus.STATUS_TIMEOUT then
                    sys.publish("modbus_log", {
                        port_type = port_type,
                        message = "写[地址" .. addr .. "]超时"
                    })
                end
            end
        else
            local read_config = {
                slave_id = slave_id,
                reg_type = reg_type,
                start_addr = physical_addr,
                reg_count = 1,
                timeout = timeout
            }

            local result = instance.modbus:read(read_config)

            if result.raw_request then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "[TX] " .. format_hex(result.raw_request)
                })
            end

            if result.raw_response then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "[RX] " .. format_hex(result.raw_response)
                })
            end

            if result.status == exmodbus.STATUS_SUCCESS then
                local value = result.data[physical_addr] or 0
                update_data[addr] = value
                registered_registers[addr].value = value
            elseif result.status == exmodbus.STATUS_DATA_INVALID then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "读[地址" .. addr .. "]数据损坏/校验失败"
                })
            elseif result.status == exmodbus.STATUS_TIMEOUT then
                sys.publish("modbus_log", {
                    port_type = port_type,
                    message = "读[地址" .. addr .. "]超时"
                })
            end
        end
    end

    if next(update_data) then
        sys.publish("modbus_data_update", {
            port_type = port_type,
            data = update_data
        })
    end
end

--[[
轮询任务函数：循环执行轮询，通过 is_polling 标志控制退出
@local
@function polling_task
@param port_type string 端口类型标识
]]
local function polling_task(port_type)
    while true do
        local instance = instances[port_type]
        if not instance or not instance.is_polling then
            break
        end

        polling_once(port_type)

        local config = modbus_rtu_master.get_config()
        local interval = config.poll_interval or 1000
        sys.wait(interval)
    end
    log.info(TASK_NAME, "轮询任务已退出")
end

--[[
启动轮询任务
@local
@function start_polling_timer
@param port_type string 端口类型标识
]]
local function start_polling_timer(port_type)
    local instance = instances[port_type]
    if not instance then
        return
    end

    instance.is_polling = true
    sys.taskInit(polling_task, port_type)

    log.info(TASK_NAME, "轮询任务已启动")
end

--[[
停止轮询任务
@local
@function stop_polling_timer
@param port_type string 端口类型标识
]]
local function stop_polling_timer(port_type)
    local instance = instances[port_type]
    if not instance then
        return
    end

    instance.is_polling = false
    log.info(TASK_NAME, "轮询任务已停止")
end

-- ========================================
-- 配置管理
-- ========================================

--[[
@function modbus_rtu_master.get_config
@summary 获取配置
@return table 配置表
]]
function modbus_rtu_master.get_config()
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
@function modbus_rtu_master.save_config
@summary 保存配置（支持部分更新）
@param config table 配置表，支持完整配置或部分字段更新
@return boolean 是否保存成功
]]
function modbus_rtu_master.save_config(config)
    local existing_config = modbus_rtu_master.get_config()

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

-- ========================================
-- 主站启停
-- ========================================

--[[
@function modbus_rtu_master.start
@summary 启动 RTU 主站
@param port_type string 端口类型标识
@return boolean, string|nil 是否启动成功及错误原因
]]
function modbus_rtu_master.start(port_type)
    if instances[port_type] then
        log.warn(TASK_NAME, "instance already exists", port_type)
        return false, "instance_already_exists"
    end

    local config = modbus_rtu_master.get_config()

    log.info(TASK_NAME, "starting", "port=" .. port_type,
        "uart=" .. config.uart_id,
        "baud=" .. config.baud_rate,
        "parity=" .. config.parity,
        "slave=" .. config.slave_id)

    local create_config = {
        mode = exmodbus.RTU_MASTER,
        uart_id = config.uart_id,
        baud_rate = config.baud_rate,
        data_bits = config.data_bits,
        stop_bits = config.stop_bits,
        parity_bits = parse_parity(config.parity),
        byte_order = config.byte_order or 0,
        rs485_dir_gpio = config.rs485_dir_gpio or 17,
        rs485_dir_rx_level = config.rs485_dir_rx_level or 0,
    }

    local modbus = exmodbus.create(create_config)
    if not modbus then
        log.error(TASK_NAME, "exmodbus create failed")
        return false, "exmodbus_create_failed"
    end

    log.info(TASK_NAME, "exmodbus created successfully, RTU master on uart" .. config.uart_id)

    -- 配置 485 芯片供电管脚为输出并拉高，使能 485 芯片供电
    -- 默认值 -1 表示不使用供电控制功能
    local vcc_gpio = config.rs485_vcc_gpio or -1
    if vcc_gpio >= 0 then
        gpio.setup(vcc_gpio, 1, gpio.PULLUP)
        log.info(TASK_NAME, "485芯片供电管脚已使能", "gpio=" .. vcc_gpio)
    end

    local instance = {
        modbus = modbus,
        is_polling = false,
        rs485_vcc_gpio = vcc_gpio
    }
    instances[port_type] = instance

    start_polling_timer(port_type)

    log.info(TASK_NAME, "RTU Master running")

    return true, nil
end

--[[
@function modbus_rtu_master.stop
@summary 停止 RTU 主站
@param port_type string 端口类型标识
@return boolean, string|nil 是否停止成功及错误原因
]]
function modbus_rtu_master.stop(port_type)
    local instance = instances[port_type]
    if not instance then
        log.warn(TASK_NAME, "instance not found", port_type)
        return false, "instance_not_found"
    end

    log.info(TASK_NAME, "stopping", port_type)

    stop_polling_timer(port_type)

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

-- ========================================
-- 读写操作
-- ========================================

--[[
@function modbus_rtu_master.read
@summary 主站发起读请求
@param port_type string 端口类型标识
@param config table 读取配置
@return table 响应结果
]]
function modbus_rtu_master.read(port_type, config)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "主站未启动，无法读取"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    local default_config = modbus_rtu_master.get_config()

    local read_config = {
        slave_id = config.slave_id or default_config.slave_id or 1,
        reg_type = config.reg_type,
        start_addr = config.start_addr,
        reg_count = config.reg_count,
        timeout = config.timeout
    }

    if not read_config.reg_type or not read_config.start_addr or not read_config.reg_count then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "读请求参数不完整"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    local result = instance.modbus:read(read_config)

    if result.raw_request then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "[TX] " .. format_hex(result.raw_request)
        })
    end

    if result.raw_response then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "[RX] " .. format_hex(result.raw_response)
        })
    end

    return result
end

--[[
@function modbus_rtu_master.write
@summary 主站发起写请求
@param port_type string 端口类型标识
@param config table 写入配置
@return table 响应结果
]]
function modbus_rtu_master.write(port_type, config)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "主站未启动，无法写入"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    local default_config = modbus_rtu_master.get_config()

    local write_config = {
        slave_id = config.slave_id or default_config.slave_id or 1,
        reg_type = config.reg_type,
        start_addr = config.start_addr,
        data = config.data,
        timeout = config.timeout
    }

    if not write_config.reg_type or not write_config.start_addr or not write_config.data then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "写请求参数不完整"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    local result = instance.modbus:write(write_config)

    if result.raw_request then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "[TX] " .. format_hex(result.raw_request)
        })
    end

    if result.raw_response then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "[RX] " .. format_hex(result.raw_response)
        })
    end

    return result
end

return modbus_rtu_master
