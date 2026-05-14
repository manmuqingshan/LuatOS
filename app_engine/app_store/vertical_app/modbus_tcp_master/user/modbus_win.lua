--[[
@module  modbus_win
@summary Modbus TCP 主站 - 通讯管理页面模块
@version 1.0
@date    2026.05.11
@usage
本模块为通讯管理页面，显示 Modbus TCP 主站配置入口。
订阅"OPEN_MODBUS_WIN"事件打开窗口。
]]

local modbus_tcp_master = require("modbus_tcp_master")

-- ========================================
-- 模块级变量
-- ========================================

-- 窗口和容器引用
local win_id = nil
local main_container = nil
local content_container = nil
local title_bar = nil
local card1_container = nil
local shared_keyboard = nil

-- WiFi 状态显示标签
local wifi_status_label = nil
local wifi_ip_label = nil
local wifi_netmask_label = nil
local wifi_gateway_label = nil
local wifi_check_timer_id = nil

-- TCP 主站控制
local tcp_toggle_btn = nil
local tcp_is_open = false
local tcp_config_inputs = {}

-- 通讯日志
local tcp_log_container = nil
local tcp_log_labels = {}

-- 寄存器映射表
local tcp_reg_table = nil
local card2_container = nil
local register_dialog = nil
local register_overlay = nil
local register_list = {}
local register_row_map = {}

-- ========================================
-- 通用函数
-- ========================================

--[[
内部函数：返回主菜单
@local
@function go_back
@return nil
]]
local function go_back()
    exwin.close(win_id)
end

--[[
内部函数：添加通讯日志行
@local
@function add_log
@param log_container object 日志容器
@param log_labels table 日志标签列表
@param log_text string 日志文本
]]
local function add_log(log_container, log_labels, log_text)
    if not log_container then return end

    local line_height = 32
    local max_lines = 6

    local new_label = airui.label({
        parent = log_container,
        x = 5,
        y = #log_labels * line_height,
        w = 280,
        h = line_height,
        text = log_text,
        font_size = 12,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    table.insert(log_labels, new_label)

    -- 超过最大行数时移除最旧的行
    if #log_labels > max_lines then
        local old_label = table.remove(log_labels, 1)
        if old_label then
            old_label:destroy()
        end
        -- 重新排列剩余标签的y坐标
        for i, label in ipairs(log_labels) do
            label:set_pos(5, (i - 1) * line_height)
        end
    end
end

--[[
内部函数：清空日志
@local
@function clear_logs
@param log_container object 日志容器
@param log_labels table 日志标签列表
]]
local function clear_logs(log_container, log_labels)
    if not log_container then return end
    for i = #log_labels, 1, -1 do
        local label = log_labels[i]
        if label then
            label:destroy()
        end
        log_labels[i] = nil
    end
end

--[[
内部函数：创建日志面板
@local
@function create_log_panel
@param tab_prefix string 日志前缀标识
@param parent_container object 父容器
@param y_button number 按钮y坐标
@param y_container number 容器y坐标
@param clear_func function 清空回调
@return object 日志内容容器
]]
local function create_log_panel(tab_prefix, parent_container, y_button, y_container, clear_func)
    -- 标题标签
    airui.label({
        parent = parent_container,
        x = 15,
        y = y_button + 5,
        w = 100,
        h = 26,
        text = "实时通讯日志",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 清空按钮
    airui.button({
        parent = parent_container,
        x = 245,
        y = y_button,
        w = 60,
        h = 20,
        text = "清空",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = function()
            log.info("清空" .. tab_prefix .. "日志")
            clear_func()
        end
    })

    -- 外层白色卡片
    local card_container = airui.container({
        parent = parent_container,
        x = 10,
        y = y_container,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    -- 内层灰色日志区域
    local log_container = airui.container({
        parent = card_container,
        x = 5,
        y = 5,
        w = 290,
        h = 160,
        color = 0xF5F5F5
    })

    return log_container
end

-- ========================================
-- WiFi 状态检查
-- ========================================

--[[
内部函数：WiFi状态检查任务
@local
@function wifi_check_task
@return nil
]]
local function wifi_check_task()
    local is_connected = wlan.ready()
    if is_connected then
        local ip, netmask, gw = socket.localIP(socket.LWIP_STA)
        if wifi_status_label then
            wifi_status_label:set_text("已连接")
            wifi_status_label:set_color(0x4CAF50)
        end
        if wifi_ip_label then
            wifi_ip_label:set_text(ip or "--")
        end
        if wifi_netmask_label then
            wifi_netmask_label:set_text(netmask or "--")
        end
        if wifi_gateway_label then
            wifi_gateway_label:set_text(gw or "--")
        end
    else
        if wifi_status_label then
            wifi_status_label:set_text("未连接")
            wifi_status_label:set_color(0xFF5722)
        end
        if wifi_ip_label then
            wifi_ip_label:set_text("--")
        end
        if wifi_netmask_label then
            wifi_netmask_label:set_text("--")
        end
        if wifi_gateway_label then
            wifi_gateway_label:set_text("--")
        end
    end
end

--[[
内部函数：WiFi断开时的处理
@local
@function wifi_disconnect_handler
@param status string WiFi状态
]]
local function wifi_disconnect_handler(status)
    if status == "DISCONNECTED" and tcp_is_open then
        log.info("modbus_tcp", "WiFi断开，主站停止")
        modbus_tcp_master.stop("tcp_master")
        tcp_is_open = false
        if tcp_toggle_btn then
            tcp_toggle_btn:set_text("打开")
            tcp_toggle_btn:set_style({
                bg_color = 0x4CAF50,
                border_color = 0x4CAF50,
                text_color = 0xFFFFFF
            })
        end
    end
    wifi_check_task()
end

-- ========================================
-- Modbus TCP 主站配置
-- ========================================

--[[
内部函数：将配置应用到UI输入框
@local
@function tcp_apply_config
@param config table 配置表
]]
local function tcp_apply_config(config)
    if not content_container then return end
    if not config then return end

    if tcp_config_inputs["target_ip"] and tcp_config_inputs["target_ip"].ui then
        tcp_config_inputs["target_ip"].ui:set_text(tostring(config.target_ip or "192.168.1.100"))
    end
    if tcp_config_inputs["target_port"] and tcp_config_inputs["target_port"].ui then
        tcp_config_inputs["target_port"].ui:set_text(tostring(config.target_port or 502))
    end
    if tcp_config_inputs["slave_id"] and tcp_config_inputs["slave_id"].ui then
        tcp_config_inputs["slave_id"].ui:set_text(tostring(config.slave_id or 1))
    end
    if tcp_config_inputs["poll_interval"] and tcp_config_inputs["poll_interval"].ui then
        tcp_config_inputs["poll_interval"].ui:set_text(tostring(config.poll_interval or 1000))
    end
    if tcp_config_inputs["timeout"] and tcp_config_inputs["timeout"].ui then
        tcp_config_inputs["timeout"].ui:set_text(tostring(config.timeout or 3000))
    end

    log.info("modbus_tcp", "配置已加载到UI")
end

--[[
内部函数：校验并保存主站配置
@local
@function tcp_validate_config
]]
local function tcp_validate_config()
    -- 运行中不允许修改配置
    if tcp_is_open then
        local msgbox = airui.msgbox({
            title = "提示",
            text = "请先关闭通讯再进行配置",
            buttons = { "确定" },
            on_action = function(self)
                self:hide()
            end
        })
        msgbox:show()
        return
    end

    -- 取出目标从站IP
    local target_ip = "192.168.1.100"
    if tcp_config_inputs["target_ip"] and tcp_config_inputs["target_ip"].ui then
        target_ip = tcp_config_inputs["target_ip"].ui:get_text() or "192.168.1.100"
    end

    -- 取出目标端口
    local target_port = 502
    if tcp_config_inputs["target_port"] and tcp_config_inputs["target_port"].ui then
        target_port = tonumber(tcp_config_inputs["target_port"].ui:get_text()) or 502
    end

    -- 取出从站地址，校验范围
    local slave_id_input = tcp_config_inputs["slave_id"]
    if slave_id_input and slave_id_input.ui then
        local slave_id = tonumber(slave_id_input.ui:get_text())
        if not slave_id or slave_id < 1 or slave_id > 247 then
            local msgbox = airui.msgbox({
                title = "提示",
                text = "从站地址必须在1-247范围内",
                buttons = { "确定" },
                on_action = function(self)
                    self:hide()
                end
            })
            msgbox:show()
            return
        end
    end

    -- 取出轮询间隔
    local poll_interval = 1000
    if tcp_config_inputs["poll_interval"] and tcp_config_inputs["poll_interval"].ui then
        poll_interval = tonumber(tcp_config_inputs["poll_interval"].ui:get_text()) or 1000
    end
    if poll_interval < 1000 then
        airui.msgbox({
            title = "提示",
            text = "轮询间隔不能小于1000ms",
            buttons = { "好的" },
            on_action = function(self, label)
                if label == "好的" then
                    self:hide()
                end
            end
        })
        return
    end

    -- 取出超时时间
    local timeout = 3000
    if tcp_config_inputs["timeout"] and tcp_config_inputs["timeout"].ui then
        timeout = tonumber(tcp_config_inputs["timeout"].ui:get_text()) or 3000
    end
    if timeout < 1000 then
        airui.msgbox({
            title = "提示",
            text = "超时时间不能小于1000ms",
            buttons = { "好的" },
            on_action = function(self, label)
                if label == "好的" then
                    self:hide()
                end
            end
        })
        return
    end

    local config = {
        target_ip = target_ip,
        target_port = target_port,
        slave_id = tonumber(slave_id_input.ui:get_text()),
        poll_interval = poll_interval,
        timeout = timeout,
    }

    modbus_tcp_master.save_config(config)

    log.info("modbus_tcp", "配置保存成功", "ip=" .. target_ip, "port=" .. target_port, "slave=" .. config.slave_id, "interval=" .. poll_interval, "timeout=" .. timeout)
end

-- ========================================
-- 寄存器映射表
-- ========================================

--[[
内部函数：添加寄存器行到UI
@local
@function add_register_row
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
]]
local function add_register_row(addr, name, value, rw)
    -- 校验读写属性默认值
    local rw_val = rw or "r"
    local rw_text = rw_val == "w" and "写" or "读"

    -- 根据地址范围限制数值范围
    if addr >= 30001 then
        value = math.max(0, math.min(65535, value or 0))
    elseif addr >= 10001 then
        value = math.max(0, math.min(1, value or 0))
    elseif addr >= 40001 then
        value = math.max(0, math.min(65535, value or 0))
    else
        value = math.max(0, math.min(1, value or 0))
    end

    -- 注册到 modbus_tcp_master
    modbus_tcp_master.add_register(addr, name, value, rw_val)

    -- 检查地址是否已存在
    if register_row_map[addr] then
        local row = register_row_map[addr]
        tcp_reg_table:set_cell_text(row, 1, name)
        tcp_reg_table:set_cell_text(row, 2, tostring(value))
        tcp_reg_table:set_cell_text(row, 3, rw_text)
        register_list[row].name = name
        register_list[row].value = value
        register_list[row].rw = rw_val
        return
    end

    -- 地址不存在，添加新行
    local row = #register_list + 1
    local addr_str = string.format("%05d", addr)
    local data = {
        addr_str,
        name,
        tostring(value),
        rw_text
    }
    tcp_reg_table:insert("row", row, data)
    table.insert(register_list, {addr = addr, name = name, value = value, rw = rw_val})
    register_row_map[addr] = row
end

--[[
内部函数：从UI移除寄存器行
@local
@function remove_register_row
@param addr number 寄存器地址
]]
local function remove_register_row(addr)
    local row = register_row_map[addr]
    if row then
        tcp_reg_table:remove("row", row)
        table.remove(register_list, row)
        register_row_map[addr] = nil
        -- 更新后续行的索引映射
        for a, r in pairs(register_row_map) do
            if r > row then
                register_row_map[a] = r - 1
            end
        end
    end
end

--[[
内部函数：更新寄存器行显示值
@local
@function update_register_row
@param addr number 寄存器地址
@param value number 寄存器值
]]
local function update_register_row(addr, value)
    local row = register_row_map[addr]
    if row and tcp_reg_table then
        tcp_reg_table:set_cell_text(row, 2, tostring(value))
        if register_list[row] then
            register_list[row].value = value
        end
    end
end

--[[
内部函数：关闭寄存器弹窗
@local
@function close_register_dialog
]]
local function close_register_dialog()
    if register_dialog then
        register_dialog:destroy()
        register_dialog = nil
    end
    if register_overlay then
        register_overlay:destroy()
        register_overlay = nil
    end
end

--[[
内部函数：显示创建寄存器弹窗
@local
@function show_create_register_dialog
]]
local function show_create_register_dialog()
    register_overlay = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0x000000,
        color_opacity = 100
    })

    register_dialog = airui.container({
        parent = main_container,
        x = 20,
        y = 100,
        w = 280,
        h = 230,
        color = 0xFFFFFF,
        radius = 10
    })

    -- 标题
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 10,
        w = 260,
        h = 30,
        text = "创建寄存器",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 逻辑地址输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 50,
        w = 70,
        h = 35,
        text = "逻辑地址：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local addr_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 45,
        w = 190,
        h = 25,
        placeholder = "输入地址，如40001",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end,
        })
    })

    -- 功能名称输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 85,
        w = 70,
        h = 35,
        text = "功能名称：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local name_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 80,
        w = 190,
        h = 25,
        placeholder = "输入功能名称",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "pinyin_26",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 数值输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 115,
        w = 70,
        h = 35,
        text = "数值：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local value_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 110,
        w = 190,
        h = 25,
        text = "0",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 读写选择标签
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 145,
        w = 70,
        h = 35,
        text = "读/写：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 读写选择下拉框（索引0=读，索引1=写）
    local rw_dropdown = airui.dropdown({
        parent = register_dialog,
        x = 80,
        y = 145,
        w = 190,
        h = 25,
        options = { "读", "写" },
        default_index = 0,
    })

    -- 取消按钮
    airui.button({
        parent = register_dialog,
        x = 30,
        y = 185,
        w = 100,
        h = 30,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = 0x9E9E9E,
            border_color = 0x9E9E9E,
            text_color = 0xFFFFFF
        },
        on_click = close_register_dialog
    })

    -- 确定按钮
    airui.button({
        parent = register_dialog,
        x = 150,
        y = 185,
        w = 100,
        h = 30,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = function()
            local addr = tonumber(addr_input:get_text())
            local name = name_input:get_text() or ""
            local value = tonumber(value_input:get_text()) or 0
            -- 获取用户选择的读写属性：索引0=读("r"), 索引1=写("w")
            local rw = rw_dropdown:get_selected() == 1 and "w" or "r"

            if addr then
                -- 校验：检查地址范围是否有效
                if addr < 1 or addr > 49999 then
                    airui.msgbox({
                        title = "提示",
                        text = "逻辑地址超出范围（1-49999）",
                        buttons = { "确定" },
                        on_action = function(self) self:hide() end
                    }):show()
                    return
                end

                -- 校验：写操作不允许对只读寄存器（1xxxx/3xxxx）
                if rw == "w" and ((addr >= 10001 and addr <= 19999) or (addr >= 30001 and addr <= 39999)) then
                    airui.msgbox({
                        title = "提示",
                        text = "该地址为只读寄存器，不支持写操作",
                        buttons = { "确定" },
                        on_action = function(self) self:hide() end
                    }):show()
                    return
                end

                add_register_row(addr, name, value, rw)
            end
            close_register_dialog()
        end
    })
end

--[[
内部函数：显示删除寄存器弹窗
@local
@function show_delete_register_dialog
]]
local function show_delete_register_dialog()
    register_overlay = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0x000000,
        color_opacity = 100
    })

    register_dialog = airui.container({
        parent = main_container,
        x = 20,
        y = 100,
        w = 280,
        h = 170,
        color = 0xFFFFFF,
        radius = 10
    })

    -- 标题
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 10,
        w = 260,
        h = 30,
        text = "删除寄存器",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 逻辑地址输入
    airui.label({
        parent = register_dialog,
        x = 10,
        y = 50,
        w = 70,
        h = 35,
        text = "逻辑地址：",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local addr_input = airui.textarea({
        parent = register_dialog,
        x = 80,
        y = 45,
        w = 190,
        h = 25,
        placeholder = "输入地址，如40001",
        keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 320,
            h = 120,
            mode = "numeric",
            auto_hide = true,
            preview = true,
            preview_height = 40,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    -- 取消按钮
    airui.button({
        parent = register_dialog,
        x = 30,
        y = 120,
        w = 100,
        h = 30,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = 0x9E9E9E,
            border_color = 0x9E9E9E,
            text_color = 0xFFFFFF
        },
        on_click = close_register_dialog
    })

    -- 确定按钮
    airui.button({
        parent = register_dialog,
        x = 150,
        y = 120,
        w = 100,
        h = 30,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = function()
            local addr = tonumber(addr_input:get_text())

            if addr and register_row_map[addr] then
                remove_register_row(addr)
                modbus_tcp_master.remove_register(addr)
            end
            close_register_dialog()
        end
    })
end

--[[
内部函数：创建寄存器映射表卡片
@local
@function create_register_table
@param parent object 父容器
@param y number 标签y坐标
]]
local function create_register_table(parent, y)
    airui.label({
        parent = parent,
        x = 15,
        y = y + 5,
        w = 100,
        h = 26,
        text = "寄存器映射表",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 创建按钮
    airui.button({
        parent = parent,
        x = 180,
        y = y,
        w = 60,
        h = 20,
        text = "创建",
        font_size = 14,
        style = {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = show_create_register_dialog
    })

    -- 删除按钮
    airui.button({
        parent = parent,
        x = 245,
        y = y,
        w = 60,
        h = 20,
        text = "删除",
        font_size = 14,
        style = {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        },
        on_click = show_delete_register_dialog
    })

    -- 表格容器
    card2_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    -- 表格（初始只有标题行）
    tcp_reg_table = airui.table({
        parent = card2_container,
        x = 5,
        y = 5,
        w = 290,
        h = 160,
        rows = 1,
        cols = 4,
        col_width = 70,
        row_height = 25,
        style = {
            bg_color = 0xFFFFFF,
            cell_bg_color = 0xFFFFFF,
            cell_border_color = 0xCCCCCC,
            cell_border_width = 1,
            cell_text_color = 0x333333,
            cell_font_size = 12,
            cell_text_align = airui.TEXT_ALIGN_CENTER
        }
    })

    -- 标题行
    tcp_reg_table:set_cell_text(0, 0, "地址")
    tcp_reg_table:set_cell_text(0, 1, "功能")
    tcp_reg_table:set_cell_text(0, 2, "当前值")
    tcp_reg_table:set_cell_text(0, 3, "读/写")
end

-- ========================================
-- 事件订阅
-- ========================================

-- 订阅通讯日志事件
sys.subscribe("modbus_log", function(data)
    if data.port_type == "tcp_master" then
        local time_str = os.date("%H:%M:%S")
        add_log(tcp_log_container, tcp_log_labels, time_str .. " " .. data.message)
    end
end)

-- 订阅寄存器数据更新事件（主站从从站读取到数据时触发）
sys.subscribe("modbus_data_update", function(data)
    if data.port_type == "tcp_master" then
        local register_data = data.data or {}
        for addr, value in pairs(register_data) do
            update_register_row(addr, value)
        end
    end
end)

-- ========================================
-- UI 构建
-- ========================================

--[[
内部函数：创建标题栏
@local
@function create_title_bar
@param parent object 父容器
]]
local function create_title_bar(parent)
    title_bar = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 320,
        h = 60,
        color = 0x5C6BC0
    })

    -- 返回按钮
    local back_btn = airui.container({
        parent = title_bar,
        x = 5,
        y = 15,
        w = 30,
        h = 25,
        color = 0xFFFFFF,
        radius = 20,
        color_opacity = 100,
        on_click = function()
            log.info("返回主菜单")
            go_back()
        end
    })
    airui.label({
        parent = back_btn,
        x = 0,
        y = 5,
        w = 30,
        h = 25,
        text = "←",
        font_size = 20,
        color = 0x5C6BC0,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = title_bar,
        x = 0,
        y = 20,
        w = 320,
        h = 28,
        text = "Modbus TCP 主站配置",
        font_size = 22,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
内部函数：创建参数配置卡片
@local
@function create_config_card
@param parent object 父容器
@param y number 起始y坐标
]]
local function create_config_card(parent, y)
    -- 区域标题
    airui.label({
        parent = parent,
        x = 15,
        y = y + 5,
        w = 100,
        h = 26,
        text = "参数配置",
        font_size = 16,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 设置按钮
    airui.button({
        parent = parent,
        x = 180,
        y = y,
        w = 60,
        h = 20,
        text = "设置",
        font_size = 14,
        style = {
            bg_color = 0x5C6BC0,
            border_color = 0x5C6BC0,
            text_color = 0xFFFFFF
        },
        on_click = tcp_validate_config
    })

    -- 打开/关闭按钮
    tcp_toggle_btn = airui.button({
        parent = parent,
        x = 245,
        y = y,
        w = 60,
        h = 20,
        text = tcp_is_open and "关闭" or "打开",
        font_size = 14,
        style = tcp_is_open and {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        } or {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = function()
            tcp_is_open = not tcp_is_open

            if tcp_is_open then
                -- 打开前检查WiFi连接
                if not wlan.ready() then
                    airui.msgbox({
                        title = "提示",
                        text = "WiFi未连接，请先连接WiFi",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                        end
                    }):show()
                    tcp_is_open = false
                    return
                end

                log.info("modbus_tcp", "启动TCP主站")
                local ok, err = modbus_tcp_master.start("tcp_master")
                if not ok then
                    local err_msg = (err == "instance_already_exists") and "实例已存在，请先停止"
                        or (err == "exmodbus_create_failed") and "exmodbus创建失败"
                        or "启动失败"
                    airui.msgbox({
                        title = "启动失败",
                        text = err_msg,
                        buttons = { "确定" }
                    }):show()
                    tcp_is_open = false
                else
                    tcp_toggle_btn:set_text("关闭")
                    tcp_toggle_btn:set_style({
                        bg_color = 0xFF5722,
                        border_color = 0xFF5722,
                        text_color = 0xFFFFFF
                    })
                end
            else
                log.info("modbus_tcp", "停止TCP主站")
                local ok, err = modbus_tcp_master.stop("tcp_master")
                if not ok then
                    local err_msg = (err == "instance_not_found") and "实例不存在"
                        or "停止失败"
                    airui.msgbox({
                        title = "停止失败",
                        text = err_msg,
                        buttons = { "确定" }
                    }):show()
                    tcp_is_open = true
                else
                    tcp_toggle_btn:set_text("打开")
                    tcp_toggle_btn:set_style({
                        bg_color = 0x4CAF50,
                        border_color = 0x4CAF50,
                        text_color = 0xFFFFFF
                    })
                end
            end
        end
    })

    -- 配置卡片（白色背景）
    card1_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 270,
        color = 0xFFFFFF,
        radius = 8
    })

    -- ==== 第1行：目标从站IP ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 10,
        w = 130,
        h = 35,
        text = "目标从站IP",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["target_ip"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 5,
        w = 120,
        h = 25,
        text = "192.168.1.100",
        placeholder = "输入IP地址",
        max_len = 15,
        keyboard = shared_keyboard
    })}

    -- ==== 第2行：目标端口 ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 45,
        w = 130,
        h = 35,
        text = "目标端口",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["target_port"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 40,
        w = 120,
        h = 25,
        text = "502",
        placeholder = "请输入",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- ==== 第3行：从站地址 ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 80,
        w = 130,
        h = 35,
        text = "从站地址",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["slave_id"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 75,
        w = 120,
        h = 25,
        text = "1",
        placeholder = "1-247",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- ==== 第4行：轮询间隔 ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 115,
        w = 130,
        h = 35,
        text = "轮询间隔(ms)",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["poll_interval"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 110,
        w = 120,
        h = 25,
        text = "1000",
        placeholder = "毫秒",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- ==== 超时时间 ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 150,
        w = 130,
        h = 30,
        text = "超时时间(ms)",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    tcp_config_inputs["timeout"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 145,
        w = 120,
        h = 25,
        text = "3000",
        placeholder = "毫秒",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- ==== WiFi状态显示 ====
    airui.label({
        parent = card1_container,
        x = 10,
        y = 180,
        w = 130,
        h = 30,
        text = "WiFi状态",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_status_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 180,
        w = 120,
        h = 30,
        text = "未连接",
        font_size = 14,
        color = 0xFF5722,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 本机IP地址
    airui.label({
        parent = card1_container,
        x = 10,
        y = 200,
        w = 130,
        h = 30,
        text = "本机IP",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_ip_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 200,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 子网掩码
    airui.label({
        parent = card1_container,
        x = 10,
        y = 220,
        w = 130,
        h = 30,
        text = "子网掩码",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_netmask_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 220,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 网关
    airui.label({
        parent = card1_container,
        x = 10,
        y = 240,
        w = 130,
        h = 30,
        text = "网关",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    wifi_gateway_label = airui.label({
        parent = card1_container,
        x = 170,
        y = 240,
        w = 120,
        h = 30,
        text = "--",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })
end

--[[
内部函数：创建日志卡片
@local
@function create_log_card
@param parent object 父容器
@param y_label number 标签y坐标
@param y_container number 容器y坐标
]]
local function create_log_card(parent, y_label, y_container)
    tcp_log_container = create_log_panel("modbus_tcp", parent, y_label, y_container, function()
        clear_logs(tcp_log_container, tcp_log_labels)
    end)
end

-- ========================================
-- 窗口生命周期
-- ========================================

--[[
内部函数：创建完整UI
@local
@function create_ui
]]
local function create_ui()
    -- 主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xE8E9EB,
        parent = airui.screen
    })

    create_title_bar(main_container)

    -- 内容滚动区域
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 420,
        color = 0xE8E9EB
    })

    -- 共享键盘（数字模式）
    shared_keyboard = airui.keyboard({
        parent = main_container,
        x = 0,
        y = -10,
        w = 320,
        h = 120,
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        on_commit = function(self)
            self:hide()
        end
    })

    -- 参数配置卡片区域：y起点=10，卡片高度=240，结束于y=275
    create_config_card(content_container, 10)

    -- 寄存器映射表区域：参数卡片结束后启动，卡片高度=170
    -- 标题区域：y=280，表格容器：y=305，结束于y=475
    create_register_table(content_container, 310)

    -- 通讯日志区域：寄存器表结束后启动
    create_log_card(content_container, 510, 535)

    -- 启动WiFi状态定时检查
    wifi_check_timer_id = sys.timerLoopStart(wifi_check_task, 5000)
    wifi_check_task()
end

--[[
窗口创建回调
@local
@function on_create
]]
local function on_create()
    create_ui()

    -- 加载已保存的配置
    local config = modbus_tcp_master.get_config()
    tcp_apply_config(config)

    -- 订阅WiFi状态变化
    sys.subscribe("WLAN_STA_INC", wifi_disconnect_handler)
end

--[[
窗口销毁回调
@local
@function on_destroy
]]
local function on_destroy()
    log.info("关闭modbus_win窗口")

    -- 如果主站正在运行，先停止
    if tcp_is_open then
        log.info("modbus_tcp", "主站正在运行，先停止")
        modbus_tcp_master.stop("tcp_master")
        tcp_is_open = false
    end

    -- 取消WiFi事件订阅
    sys.unsubscribe("WLAN_STA_INC", wifi_disconnect_handler)

    -- 停止WiFi定时检查
    if wifi_check_timer_id then
        sys.timerStop(wifi_check_timer_id)
        wifi_check_timer_id = nil
    end

    -- 清理日志标签
    tcp_log_labels = {}
    tcp_log_container = nil

    -- 清理寄存器映射表
    if tcp_reg_table then
        tcp_reg_table:destroy()
        tcp_reg_table = nil
    end
    register_list = {}
    register_row_map = {}

    -- 清理配置输入框引用
    tcp_config_inputs = {}

    -- 清理WiFi标签引用
    wifi_status_label = nil
    wifi_ip_label = nil
    wifi_netmask_label = nil
    wifi_gateway_label = nil

    -- 销毁容器
    if content_container then
        content_container:destroy()
        content_container = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

--[[
窗口获得焦点回调
@local
@function on_get_focus
]]
local function on_get_focus()
    log.info("modbus_win", "get_focus")
end

--[[
窗口失去焦点回调
@local
@function on_lose_focus
]]
local function on_lose_focus()
    log.info("modbus_win", "lose_focus")
end

-- ========================================
-- 窗口打开入口
-- ========================================

--[[
打开窗口的处理器
@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_MODBUS_WIN", open_handler)
