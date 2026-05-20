--[[
@module  modbus_win
@summary Modbus RTU 从站 - 通讯管理页面模块
@version 1.0
@date    2026.05.18
@usage
本模块为通讯管理页面，显示 Modbus RTU 从站配置入口。
订阅"OPEN_MODBUS_WIN"事件打开窗口。
]]

local modbus_rtu_slave = require("modbus_rtu_slave")

-- ========================================
-- 模块级变量
-- ========================================

local win_id = nil
local main_container = nil
local content_container = nil
local title_bar = nil
local card1_container = nil
local shared_keyboard = nil

local rtu_toggle_btn = nil
local rtu_is_open = false
local rtu_config_inputs = {}

local rtu_log_container = nil
local rtu_log_labels = {}

local rtu_reg_table = nil
local card2_container = nil
local register_dialog = nil
local register_overlay = nil
local register_list = {}
local register_row_map = {}

-- ========================================
-- 校验位选项（与 modbus_rtu_slave.lua 保持一致）
-- ========================================

local PARITY_OPTIONS = { "无", "偶", "奇" }
local PARITY_VALUES = { "N", "E", "O" }

-- ========================================
-- 通用函数
-- ========================================

local function go_back()
    exwin.close(win_id)
end

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

    if #log_labels > max_lines then
        local old_label = table.remove(log_labels, 1)
        if old_label then
            old_label:destroy()
        end
        for i, label in ipairs(log_labels) do
            label:set_pos(5, (i - 1) * line_height)
        end
    end
end

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

local function create_log_panel(tab_prefix, parent_container, y_button, y_container, clear_func)
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

    local card_container = airui.container({
        parent = parent_container,
        x = 10,
        y = y_container,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

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
-- 配置应用
-- ========================================

local function rtu_apply_config(config)
    if not content_container then return end
    if not config then return end

    if rtu_config_inputs["uart_id"] and rtu_config_inputs["uart_id"].ui then
        rtu_config_inputs["uart_id"].ui:set_text(tostring(config.uart_id or 1))
    end
    if rtu_config_inputs["baud_rate"] and rtu_config_inputs["baud_rate"].ui then
        rtu_config_inputs["baud_rate"].ui:set_text(tostring(config.baud_rate or 9600))
    end
    if rtu_config_inputs["data_bits"] and rtu_config_inputs["data_bits"].ui then
        rtu_config_inputs["data_bits"].ui:set_text(tostring(config.data_bits or 8))
    end
    if rtu_config_inputs["stop_bits"] and rtu_config_inputs["stop_bits"].ui then
        rtu_config_inputs["stop_bits"].ui:set_text(tostring(config.stop_bits or 1))
    end
    if rtu_config_inputs["parity"] and rtu_config_inputs["parity"].ui then
        local parity_str = config.parity or "N"
        for i, v in ipairs(PARITY_VALUES) do
            if v == parity_str then
                rtu_config_inputs["parity"].ui:set_selected(i - 1)
                break
            end
        end
    end
    if rtu_config_inputs["self_addr"] and rtu_config_inputs["self_addr"].ui then
        rtu_config_inputs["self_addr"].ui:set_text(tostring(config.self_addr or 1))
    end
    if rtu_config_inputs["concat_timeout"] and rtu_config_inputs["concat_timeout"].ui then
        rtu_config_inputs["concat_timeout"].ui:set_text(tostring(config.concat_timeout or 50))
    end
    if rtu_config_inputs["rs485_dir_gpio"] and rtu_config_inputs["rs485_dir_gpio"].ui then
        rtu_config_inputs["rs485_dir_gpio"].ui:set_text(tostring(config.rs485_dir_gpio or 17))
    end
    if rtu_config_inputs["rs485_dir_rx_level"] and rtu_config_inputs["rs485_dir_rx_level"].ui then
        rtu_config_inputs["rs485_dir_rx_level"].ui:set_selected(config.rs485_dir_rx_level == 1 and 1 or 0)
    end
    if rtu_config_inputs["rs485_vcc_gpio"] and rtu_config_inputs["rs485_vcc_gpio"].ui then
        rtu_config_inputs["rs485_vcc_gpio"].ui:set_text(tostring(config.rs485_vcc_gpio or -1))
    end

    log.info("modbus_rtu", "配置已加载到UI")
end

-- ========================================
-- 配置校验与保存
-- ========================================

local function rtu_validate_config()
    if rtu_is_open then
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

    local uart_id = 1
    if rtu_config_inputs["uart_id"] and rtu_config_inputs["uart_id"].ui then
        uart_id = tonumber(rtu_config_inputs["uart_id"].ui:get_text()) or 1
    end

    local baud_rate = 9600
    if rtu_config_inputs["baud_rate"] and rtu_config_inputs["baud_rate"].ui then
        baud_rate = tonumber(rtu_config_inputs["baud_rate"].ui:get_text()) or 9600
    end

    local data_bits = 8
    if rtu_config_inputs["data_bits"] and rtu_config_inputs["data_bits"].ui then
        data_bits = tonumber(rtu_config_inputs["data_bits"].ui:get_text()) or 8
    end
    if data_bits ~= 7 and data_bits ~= 8 then
        airui.msgbox({
            title = "提示",
            text = "数据位仅支持7或8",
            buttons = { "确定" },
            on_action = function(self) self:hide() end
        }):show()
        return
    end

    local stop_bits = 1
    if rtu_config_inputs["stop_bits"] and rtu_config_inputs["stop_bits"].ui then
        stop_bits = tonumber(rtu_config_inputs["stop_bits"].ui:get_text()) or 1
    end
    if stop_bits ~= 1 and stop_bits ~= 2 then
        airui.msgbox({
            title = "提示",
            text = "停止位仅支持1或2",
            buttons = { "确定" },
            on_action = function(self) self:hide() end
        }):show()
        return
    end

    local parity_index = 0
    if rtu_config_inputs["parity"] and rtu_config_inputs["parity"].ui then
        parity_index = rtu_config_inputs["parity"].ui:get_selected()
    end
    local parity_str = PARITY_VALUES[parity_index + 1] or "N"

    local self_addr_input = rtu_config_inputs["self_addr"]
    if self_addr_input and self_addr_input.ui then
        local self_addr = tonumber(self_addr_input.ui:get_text())
        if not self_addr or self_addr < 1 or self_addr > 247 then
            airui.msgbox({
                title = "提示",
                text = "本机地址必须在1-247范围内",
                buttons = { "确定" },
                on_action = function(self) self:hide() end
            }):show()
            return
        end
    end

    local concat_timeout = 50
    if rtu_config_inputs["concat_timeout"] and rtu_config_inputs["concat_timeout"].ui then
        concat_timeout = tonumber(rtu_config_inputs["concat_timeout"].ui:get_text()) or 50
    end
    if concat_timeout < 10 or concat_timeout > 1000 then
        airui.msgbox({
            title = "提示",
            text = "字符拼接超时时间必须在10-1000ms范围内",
            buttons = { "确定" },
            on_action = function(self) self:hide() end
        }):show()
        return
    end

    local rs485_dir_gpio = 17
    if rtu_config_inputs["rs485_dir_gpio"] and rtu_config_inputs["rs485_dir_gpio"].ui then
        rs485_dir_gpio = tonumber(rtu_config_inputs["rs485_dir_gpio"].ui:get_text()) or 17
    end

    local rs485_dir_rx_level = 0
    if rtu_config_inputs["rs485_dir_rx_level"] and rtu_config_inputs["rs485_dir_rx_level"].ui then
        rs485_dir_rx_level = rtu_config_inputs["rs485_dir_rx_level"].ui:get_selected() == 1 and 1 or 0
    end

    local rs485_vcc_gpio = -1
    if rtu_config_inputs["rs485_vcc_gpio"] and rtu_config_inputs["rs485_vcc_gpio"].ui then
        rs485_vcc_gpio = tonumber(rtu_config_inputs["rs485_vcc_gpio"].ui:get_text()) or -1
    end

    local config = {
        uart_id = uart_id,
        baud_rate = baud_rate,
        data_bits = data_bits,
        stop_bits = stop_bits,
        parity = parity_str,
        self_addr = tonumber(self_addr_input.ui:get_text()),
        concat_timeout = concat_timeout,
        rs485_dir_gpio = rs485_dir_gpio,
        rs485_dir_rx_level = rs485_dir_rx_level,
        rs485_vcc_gpio = rs485_vcc_gpio,
    }

    modbus_rtu_slave.save_config(config)

    log.info("modbus_rtu", "配置保存成功",
        "uart=" .. uart_id,
        "baud=" .. baud_rate,
        "bits=" .. data_bits .. stop_bits .. parity_str,
        "addr=" .. config.self_addr,
        "timeout=" .. concat_timeout,
        "rs485_gpio=" .. rs485_dir_gpio,
        "rs485_vcc_gpio=" .. rs485_vcc_gpio)
end

-- ========================================
-- 寄存器映射表
-- ========================================

local function add_register_row(addr, name, value)
    if addr >= 30001 then
        value = math.max(0, math.min(65535, value or 0))
    elseif addr >= 10001 then
        value = math.max(0, math.min(1, value or 0))
    elseif addr >= 40001 then
        value = math.max(0, math.min(65535, value or 0))
    else
        value = math.max(0, math.min(1, value or 0))
    end

    modbus_rtu_slave.add_register(addr, name, value)

    if register_row_map[addr] then
        local row = register_row_map[addr]
        rtu_reg_table:set_cell_text(row, 1, name)
        rtu_reg_table:set_cell_text(row, 2, tostring(value))
        register_list[row].name = name
        register_list[row].value = value
        return
    end

    local row = #register_list + 1
    local addr_str = string.format("%05d", addr)
    local data = {
        addr_str,
        name,
        tostring(value)
    }
    rtu_reg_table:insert("row", row, data)
    table.insert(register_list, {addr = addr, name = name, value = value})
    register_row_map[addr] = row
end

local function remove_register_row(addr)
    local row = register_row_map[addr]
    if row then
        rtu_reg_table:remove("row", row)
        table.remove(register_list, row)
        register_row_map[addr] = nil
        for a, r in pairs(register_row_map) do
            if r > row then
                register_row_map[a] = r - 1
            end
        end
    end
end

local function update_register_row(addr, value)
    local row = register_row_map[addr]
    if row and rtu_reg_table then
        rtu_reg_table:set_cell_text(row, 2, tostring(value))
        if register_list[row] then
            register_list[row].value = value
        end
    end
end

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
        h = 200,
        color = 0xFFFFFF,
        radius = 10
    })

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

    airui.button({
        parent = register_dialog,
        x = 30,
        y = 145,
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

    airui.button({
        parent = register_dialog,
        x = 150,
        y = 145,
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

            if addr then
                add_register_row(addr, name, value)
            end
            close_register_dialog()
        end
    })
end

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
                modbus_rtu_slave.remove_register(addr)
            end
            close_register_dialog()
        end
    })
end

-- ========================================
-- 事件订阅
-- ========================================

sys.subscribe("modbus_log", function(data)
    if data.port_type == "rtu_slave" then
        local time_str = os.date("%H:%M:%S")
        add_log(rtu_log_container, rtu_log_labels, time_str .. " " .. data.message)
    end
end)

sys.subscribe("modbus_data_update", function(data)
    if data.port_type == "rtu_slave" then
        local register_data = data.data or {}
        for addr, value in pairs(register_data) do
            update_register_row(addr, value)
        end
    end
end)

sys.subscribe("modbus_register_update", function(data)
    if data.port_type == "rtu_slave" then
        update_register_row(data.addr, data.value)
    end
end)

-- ========================================
-- UI 构建
-- ========================================

local function create_title_bar(parent)
    title_bar = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 320,
        h = 60,
        color = 0x5C6BC0
    })

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

    airui.label({
        parent = title_bar,
        x = 0,
        y = 20,
        w = 320,
        h = 28,
        text = "Modbus RTU 从站配置",
        font_size = 22,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function create_config_card(parent, y)
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
        on_click = rtu_validate_config
    })

    rtu_toggle_btn = airui.button({
        parent = parent,
        x = 245,
        y = y,
        w = 60,
        h = 20,
        text = rtu_is_open and "关闭" or "打开",
        font_size = 14,
        style = rtu_is_open and {
            bg_color = 0xFF5722,
            border_color = 0xFF5722,
            text_color = 0xFFFFFF
        } or {
            bg_color = 0x4CAF50,
            border_color = 0x4CAF50,
            text_color = 0xFFFFFF
        },
        on_click = function()
            rtu_is_open = not rtu_is_open

            if rtu_is_open then
                log.info("modbus_rtu", "启动RTU从站")
                local ok, err = modbus_rtu_slave.start("rtu_slave")
                if not ok then
                    local err_msg = (err == "instance_already_exists") and "实例已存在，请先停止"
                        or (err == "exmodbus_create_failed") and "exmodbus创建失败"
                        or "启动失败"
                    airui.msgbox({
                        title = "启动失败",
                        text = err_msg,
                        buttons = { "确定" },
                        on_action = function(self) self:hide() end
                    }):show()
                    rtu_is_open = false
                else
                    rtu_toggle_btn:set_text("关闭")
                    rtu_toggle_btn:set_style({
                        bg_color = 0xFF5722,
                        border_color = 0xFF5722,
                        text_color = 0xFFFFFF
                    })
                end
            else
                log.info("modbus_rtu", "停止RTU从站")
                local ok, err = modbus_rtu_slave.stop("rtu_slave")
                if not ok then
                    local err_msg = (err == "instance_not_found") and "实例不存在"
                        or "停止失败"
                    airui.msgbox({
                        title = "停止失败",
                        text = err_msg,
                        buttons = { "确定" },
                        on_action = function(self) self:hide() end
                    }):show()
                    rtu_is_open = true
                else
                    rtu_toggle_btn:set_text("打开")
                    rtu_toggle_btn:set_style({
                        bg_color = 0x4CAF50,
                        border_color = 0x4CAF50,
                        text_color = 0xFFFFFF
                    })
                end
            end
        end
    })

    card1_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 370,
        color = 0xFFFFFF,
        radius = 8
    })

    -- 第1行：串口号
    airui.label({
        parent = card1_container,
        x = 10,
        y = 15,
        w = 140,
        h = 35,
        text = "串口号",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["uart_id"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 10,
        w = 120,
        h = 25,
        text = "1",
        placeholder = "1",
        max_len = 4,
        keyboard = shared_keyboard
    })}

    -- 第2行：波特率
    airui.label({
        parent = card1_container,
        x = 10,
        y = 50,
        w = 140,
        h = 35,
        text = "波特率",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["baud_rate"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 45,
        w = 120,
        h = 25,
        text = "9600",
        placeholder = "9600",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- 第3行：数据位
    airui.label({
        parent = card1_container,
        x = 10,
        y = 85,
        w = 140,
        h = 35,
        text = "数据位",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["data_bits"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 80,
        w = 120,
        h = 25,
        text = "8",
        placeholder = "7或8",
        max_len = 1,
        keyboard = shared_keyboard
    })}

    -- 第4行：停止位
    airui.label({
        parent = card1_container,
        x = 10,
        y = 120,
        w = 140,
        h = 35,
        text = "停止位",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["stop_bits"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 115,
        w = 120,
        h = 25,
        text = "1",
        placeholder = "1或2",
        max_len = 1,
        keyboard = shared_keyboard
    })}

    -- 第5行：校验位
    airui.label({
        parent = card1_container,
        x = 10,
        y = 155,
        w = 140,
        h = 35,
        text = "校验位",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["parity"] = {ui = airui.dropdown({
        parent = card1_container,
        x = 170,
        y = 150,
        w = 120,
        h = 25,
        options = PARITY_OPTIONS,
        default_index = 0,
    })}

    -- 第6行：本机地址
    airui.label({
        parent = card1_container,
        x = 10,
        y = 190,
        w = 140,
        h = 35,
        text = "本机地址",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["self_addr"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 185,
        w = 120,
        h = 25,
        text = "1",
        placeholder = "1-247",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- 第7行：字符拼接超时
    airui.label({
        parent = card1_container,
        x = 10,
        y = 225,
        w = 140,
        h = 35,
        text = "拼接超时(ms)",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["concat_timeout"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 220,
        w = 120,
        h = 25,
        text = "50",
        placeholder = "10-1000",
        max_len = 10,
        keyboard = shared_keyboard
    })}

    -- 第8行：RS485方向引脚
    airui.label({
        parent = card1_container,
        x = 10,
        y = 260,
        w = 140,
        h = 35,
        text = "RS485引脚",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["rs485_dir_gpio"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 255,
        w = 120,
        h = 25,
        text = "17",
        placeholder = "GPIO编号",
        max_len = 4,
        keyboard = shared_keyboard
    })}

    -- 第9行：RS485接收电平
    airui.label({
        parent = card1_container,
        x = 10,
        y = 295,
        w = 140,
        h = 35,
        text = "RS485收向",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["rs485_dir_rx_level"] = {ui = airui.dropdown({
        parent = card1_container,
        x = 170,
        y = 290,
        w = 120,
        h = 25,
        options = { "低电平", "高电平" },
        default_index = 0,
    })}

    -- 第10行：485芯片供电管脚
    airui.label({
        parent = card1_container,
        x = 10,
        y = 330,
        w = 140,
        h = 35,
        text = "485芯片供电管脚",
        font_size = 14,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    rtu_config_inputs["rs485_vcc_gpio"] = {ui = airui.textarea({
        parent = card1_container,
        x = 170,
        y = 325,
        w = 120,
        h = 25,
        text = "-1",
        placeholder = "-1=不使用",
        max_len = 4,
        keyboard = shared_keyboard
    })}
end

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

    card2_container = airui.container({
        parent = parent,
        x = 10,
        y = y + 25,
        w = 300,
        h = 170,
        color = 0xFFFFFF,
        radius = 8
    })

    rtu_reg_table = airui.table({
        parent = card2_container,
        x = 5,
        y = 5,
        w = 290,
        h = 160,
        rows = 1,
        cols = 3,
        col_width = 90,
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

    rtu_reg_table:set_cell_text(0, 0, "地址")
    rtu_reg_table:set_cell_text(0, 1, "功能")
    rtu_reg_table:set_cell_text(0, 2, "当前值")
end

local function create_log_card(parent, y_label, y_container)
    rtu_log_container = create_log_panel("modbus_rtu", parent, y_label, y_container, function()
        clear_logs(rtu_log_container, rtu_log_labels)
    end)
end

-- ========================================
-- 窗口生命周期
-- ========================================

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xE8E9EB,
        parent = airui.screen
    })

    create_title_bar(main_container)

    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 480,
        color = 0xE8E9EB
    })

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

    create_config_card(content_container, 10)
    create_register_table(content_container, 410)
    create_log_card(content_container, 610, 635)
end

local function on_create()
    create_ui()

    local config = modbus_rtu_slave.get_config()
    rtu_apply_config(config)
end

local function on_destroy()
    log.info("关闭modbus_win窗口")

    if rtu_is_open then
        log.info("modbus_rtu", "从站正在运行，先停止")
        modbus_rtu_slave.stop("rtu_slave")
        rtu_is_open = false
    end

    if rtu_reg_table then
        rtu_reg_table:destroy()
        rtu_reg_table = nil
    end
    register_list = {}
    register_row_map = {}
    rtu_log_labels = {}
    rtu_log_container = nil
    rtu_config_inputs = {}

    if content_container then
        content_container:destroy()
        content_container = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
    log.info("modbus_win", "get_focus")
end

local function on_lose_focus()
    log.info("modbus_win", "lose_focus")
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_MODBUS_WIN", open_handler)
