--[[
@module  modbus_tcp_master
@summary TCP 主站应用模块
@version 1.0
@date    2026.05.11
@author  马梦阳
@usage
本模块实现 TCP 主站功能：
1、作为 Modbus TCP 主站向从站发起读写请求
2、支持标准功能码 0x01/02/03/04/05/06/0F/10
3、通过事件机制与上层 UI 模块通信
]]

local modbus_tcp_master = {}

-- ========================================
-- 模块级变量
-- ========================================

-- exmodbus 主模块引用
local exmodbus = require("exmodbus")

-- 任务名称（用于日志标识）
local TASK_NAME = "modbus_tcp_master"

-- 实例字典（key=port_type, value=instance）
local instances = {}

-- 配置文件路径
local CONFIG_FILE = "/modbus_tcp_master_config.json"

-- 默认配置参数
local DEFAULT_CONFIG = {
    target_ip = "192.168.1.100",
    target_port = 502,
    slave_id = 1,
    poll_interval = 1000,
    timeout = 3000
}

-- ========================================
-- 轮询配置表
-- ========================================

--[[
将逻辑地址转换为 Modbus 物理地址和寄存器类型
@local
@function logical_to_physical
@param addr number 逻辑地址（1-9999, 10001-19999, 30001-39999, 40001-49999）
@return number, number|nil 成功返回物理地址和寄存器类型，失败返回 nil
]]
local function logical_to_physical(addr)
    if addr >= 1 and addr <= 9999 then
        -- 0xxxx - 线圈
        return addr - 1, exmodbus.COIL_STATUS
    elseif addr >= 10001 and addr <= 19999 then
        -- 1xxxx - 离散输入
        return addr - 10001, exmodbus.INPUT_STATUS
    elseif addr >= 30001 and addr <= 39999 then
        -- 3xxxx - 输入寄存器
        return addr - 30001, exmodbus.INPUT_REGISTER
    elseif addr >= 40001 and addr <= 49999 then
        -- 4xxxx - 保持寄存器
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

-- 寄存器注册表（地址 -> {name, value}），用于记录需要轮询的寄存器
local registered_registers = {}

--[[
@function modbus_tcp_master.add_register
@summary 注册需要轮询的寄存器地址
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
@param rw string 读写属性，"r"=只读，"w"=只写，默认"r"
]]
function modbus_tcp_master.add_register(addr, name, value, rw)
    registered_registers[addr] = {
        name = name,
        value = value or 0,
        rw = rw or "r"
    }
end

--[[
@function modbus_tcp_master.remove_register
@summary 移除已注册的寄存器地址
@param addr number 寄存器地址
]]
function modbus_tcp_master.remove_register(addr)
    registered_registers[addr] = nil
end

-- ========================================
-- 轮询任务
-- ========================================

--[[
执行一次轮询：遍历所有已注册的寄存器，根据读写属性分支执行
@local
@function polling_once
@param port_type string 端口类型标识
]]
local function polling_once(port_type)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        return
    end

    local config = modbus_tcp_master.get_config()
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
            -- ========== 写操作 ==========
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
            -- ========== 读操作 ==========
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

        local config = modbus_tcp_master.get_config()
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
@function modbus_tcp_master.get_config
@summary 获取配置
@return table 配置表
]]
function modbus_tcp_master.get_config()
    -- 配置文件不存在，使用默认配置
    if not io.exists(CONFIG_FILE) then
        log.info(TASK_NAME, "配置文件不存在，使用默认配置")
        return DEFAULT_CONFIG
    end

    -- 打开配置文件
    local file = io.open(CONFIG_FILE, "r")
    if not file then
        log.error(TASK_NAME, "读取配置文件失败：无法打开文件")
        return DEFAULT_CONFIG
    end

    -- 读取并解码JSON内容
    local content = file:read("*a")
    file:close()

    local config = json.decode(content)
    return config or DEFAULT_CONFIG
end

--[[
@function modbus_tcp_master.save_config
@summary 保存配置（支持部分更新）
@param config table 配置表，支持完整配置或部分字段更新
@return boolean 是否保存成功
]]
function modbus_tcp_master.save_config(config)
    -- 先获取已有配置，在此基础上合并新配置
    local existing_config = modbus_tcp_master.get_config()

    for key, value in pairs(config) do
        existing_config[key] = value
    end

    -- 以二进制写入模式打开文件
    local file = io.open(CONFIG_FILE, "wb")
    if not file then
        log.error(TASK_NAME, "保存配置失败：无法打开文件")
        return false
    end

    -- 编码并写入JSON
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
@function modbus_tcp_master.start
@summary 启动 TCP 主站
@param port_type string 端口类型标识
@return boolean, string|nil 是否启动成功及错误原因
]]
function modbus_tcp_master.start(port_type)
    -- 检查实例是否已存在，防止重复创建
    if instances[port_type] then
        log.warn(TASK_NAME, "instance already exists", port_type)
        return false, "instance_already_exists"
    end

    -- 读取已保存的配置
    local config = modbus_tcp_master.get_config()

    log.info(TASK_NAME, "starting", "port=" .. port_type, "target_ip=" .. (config.target_ip or "192.168.1.100"), "target_port=" .. (config.target_port or 502))

    -- 构建 TCP 主站创建参数
    -- mode=TCP_MASTER, adapter=LWIP_STA(WiFi), ip_address/port 指向目标从站
    local create_config = {
        mode = exmodbus.TCP_MASTER,
        adapter = socket.LWIP_STA,
        ip_address = config.target_ip or "192.168.1.100",
        port = config.target_port or 502,
    }

    -- 调用 exmodbus 创建 TCP 主站实例
    local modbus = exmodbus.create(create_config)
    if not modbus then
        log.error(TASK_NAME, "exmodbus create failed")
        return false, "exmodbus_create_failed"
    end

    log.info(TASK_NAME, "exmodbus created successfully, TCP master connected to " .. create_config.ip_address .. ":" .. create_config.port)

    -- 保存实例到字典
    local instance = {
        modbus = modbus,
        is_polling = false
    }
    instances[port_type] = instance

    -- 启动轮询任务
    start_polling_timer(port_type)

    log.info(TASK_NAME, "TCP Master running")

    return true, nil
end

--[[
@function modbus_tcp_master.stop
@summary 停止 TCP 主站
@param port_type string 端口类型标识
@return boolean, string|nil 是否停止成功及错误原因
]]
function modbus_tcp_master.stop(port_type)
    -- 查找实例
    local instance = instances[port_type]
    if not instance then
        log.warn(TASK_NAME, "instance not found", port_type)
        return false, "instance_not_found"
    end

    log.info(TASK_NAME, "stopping", port_type)

    -- 先停止轮询任务（设置 is_polling = false，任务下次检测到会自动退出）
    stop_polling_timer(port_type)

    -- 销毁 exmodbus 实例（关闭连接、释放 socket、停止任务）
    if instance.modbus then
        instance.modbus:destroy()
        instance.modbus = nil
    end

    -- 从字典中移除
    instances[port_type] = nil

    log.info(TASK_NAME, "stopped", port_type)
    return true, nil
end

-- ========================================
-- 读写操作
-- ========================================

--[[
@function modbus_tcp_master.read
@summary 主站发起读请求
@param port_type string 端口类型标识
@param config table 读取配置，包含以下字段：
    slave_id number 从站地址（1-247），可选，默认为配置中的 slave_id
    reg_type number 寄存器类型（exmodbus.COIL_STATUS/INPUT_STATUS/HOLDING_REGISTER/INPUT_REGISTER）
    start_addr number 起始物理地址（0-65535）
    reg_count number 寄存器数量（1-N）
    timeout number 超时时间（毫秒），可选，默认为 1000
@return table 响应结果，包含 status/data/exception_code 等字段
]]
function modbus_tcp_master.read(port_type, config)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "主站未启动，无法读取"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    -- 获取默认配置
    local default_config = modbus_tcp_master.get_config()

    -- 合并参数，使用传入的配置，缺失字段使用默认值
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
@function modbus_tcp_master.write
@summary 主站发起写请求
@param port_type string 端口类型标识
@param config table 写入配置，包含以下字段：
    slave_id number 从站地址（1-247），可选，默认为配置中的 slave_id
    reg_type number 寄存器类型（exmodbus.COIL_STATUS/HOLDING_REGISTER）
    start_addr number 起始物理地址（0-65535）
    data table 写入数据，键为寄存器地址，值为写入的数值
    timeout number 超时时间（毫秒），可选，默认为 1000
@return table 响应结果，包含 status/exception_code 等字段
]]
function modbus_tcp_master.write(port_type, config)
    local instance = instances[port_type]
    if not instance or not instance.modbus then
        sys.publish("modbus_log", {
            port_type = port_type,
            message = "主站未启动，无法写入"
        })
        return {status = exmodbus.STATUS_PARAM_INVALID}
    end

    -- 获取默认配置
    local default_config = modbus_tcp_master.get_config()

    -- 合并参数
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

return modbus_tcp_master
