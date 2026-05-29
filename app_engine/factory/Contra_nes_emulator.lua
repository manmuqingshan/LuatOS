--[[
@module  nes_emulator
@summary NES/FC 模拟器 AirUI 应用模块（使用 airui.nes 组件）
@version 3.1
@date    2026.05.30
@author  江访

实体按键由本模块自行注册 GPIO（exapp 沙箱内直连，避免跨 VM 事件丢失）。
引脚映射从 _G.project_config.nes_keys 读取，不再硬编码。

界面说明：
  - 启动后直接加载指定 ROM，进入游戏运行屏
  - 顶栏 Back 按钮 + airui.nes 组件 + 触控按键区
  - Back 按钮：销毁 NES 组件并退出应用
]]

local nes_emulator = {}

-- =========================================================
-- 底层库可用性检查
-- =========================================================

-- airui.nes 是 airui 内建组件，固件未启用时该函数不存在
local has_nes = type(airui) == "table" and type(airui.nes) == "function"
if not has_nes then
    log.warn("nes_emu", "airui.nes 不可用（固件未启用 NES 支持）")
end

-- =========================================================
-- 颜色常量（固定值，与分辨率无关）
-- =========================================================

local ROOT_BG     = 0x0A0A1A
local HEADER_BG   = 0x16213E
local ITEM_BG     = 0x1E2A3A
local ITEM_HL_BG  = 0x2A3F5F
local ACCENT      = 0x4FC3F7
local TEXT_COLOR  = 0xE0E0E0
local HINT_COLOR  = 0x9E9E9E

-- ROM 文件路径（exapp 数据目录下）
local ROM_PATH = "/luadb/data/Contra1.nes"

local SW, SH = lcd.getSize()
print("nes_emu", "Screen size:", SW, "x", SH)
local HEADER_H = 52
-- NES 缩放：优先 2 倍；高度不足时降为 1 倍
local min_ctrl_h = SW >= 512 and 60 or 120
local NES_SCALE = ((SH - HEADER_H - min_ctrl_h) >= 240 * 2) and 2 or 1

-- =========================================================
-- 内部状态
-- =========================================================

local host_win_id   = nil     -- exwin 窗口句柄
local root_ui       = nil     -- 选择屏根容器
local game_ui       = nil     -- 游戏运行容器
local nes_widget    = nil     -- airui.nes 组件句柄

-- =========================================================
-- 实体按键 GPIO 管理（引脚映射从 project_config.nes_keys 读取）
-- =========================================================

local DEBOUNCE_MS = 20          -- 硬件消抖延迟（毫秒）
local gpio_pins = {}            -- 已注册的 GPIO 引脚列表，用于释放

-- 从 NES_KEY_XXX 全名提取短名（如 "NES_KEY_UP" → "UP"）
local function short_name(key_name)
    return key_name:match("NES_KEY_(.+)$") or key_name
end

-- 按键类型分类，不同类型走不同处理策略
local function classify_key(key_name)
    if key_name:find("NES_KEY_UP") or key_name:find("NES_KEY_DOWN") or
       key_name:find("NES_KEY_LEFT") or key_name:find("NES_KEY_RIGHT") then
        return "direction"
    end
    if key_name:find("NES_KEY_A") or key_name:find("NES_KEY_B") then
        return "action"
    end
    if key_name:find("NES_KEY_RETURN") or key_name:find("NES_KEY_START") or
       key_name:find("NES_KEY_SELECT") then
        return "control"
    end
    return "unknown"
end

-- 控制键防抖状态（短名 → 上次触发时间）
local ctrl_last_press = {}
local CTRL_SW_DEBOUNCE_MS = 200

-- 注册所有实体按键 GPIO 中断
-- 引脚映射从 _G.project_config.nes_keys 读取，兼容旧版 _G.NES_KEY_CONFIG
local function setup_gpio_keys()
    -- 优先读取全局配置，回退 project_config
    local key_cfg = _G.NES_KEY_CONFIG
    if not key_cfg or type(key_cfg) ~= "table" or #key_cfg == 0 then
        local pc = _G.project_config
        if pc and pc.nes_keys and type(pc.nes_keys) == "table" then
            key_cfg = pc.nes_keys
        end
    end
    if not key_cfg or #key_cfg == 0 then
        log.warn("nes_emu", "no nes_keys config, skip GPIO")
        return
    end

    local count = 0
    for _, entry in ipairs(key_cfg) do
        local pin = entry.pin
        local key_name = entry.key
        local key_type = classify_key(key_name)
        local sname = short_name(key_name)
        local key_code = airui[key_name]

        if not key_code then
            log.warn("nes_emu", "unknown key:", key_name, "-> GPIO", pin)
        end

        -- 硬件消抖（20ms）
        gpio.debounce(pin, DEBOUNCE_MS, 1)

        -- 根据按键类型创建 GPIO 回调
        local callback
        if key_type == "direction" then
            -- 方向键：双边沿 → 直接转发 nes_widget:key
            callback = function(val)
                if nes_widget then
                    nes_widget:key(key_code, val == 0 and 1 or 0)
                end
            end
        elseif key_type == "action" then
            -- 动作键 A/B：双边沿 → 直接转发
            callback = function(val)
                if nes_widget then
                    nes_widget:key(key_code, val == 0 and 1 or 0)
                end
            end
        elseif key_type == "control" then
            -- 控制键：仅按下沿 + 软件防抖，避免重复触发 exwin.close
            callback = function(val)
                if val ~= 0 then return end  -- 只响应按下沿（低电平）
                local now = mcu and mcu.ticks and mcu.ticks() or 0
                local last = ctrl_last_press[sname] or 0
                if now - last < CTRL_SW_DEBOUNCE_MS then return end
                ctrl_last_press[sname] = now
                -- 通过 nes_widget:key 传入按键事件
                if sname == "RETURN" then
                    -- RETURN：游戏中停止，选择屏退出
                    if nes_widget then
                        log.info("nes_emu", "entity key RETURN -> stop game")
                        stop_game()
                    else
                        log.info("nes_emu", "entity key RETURN -> exit app")
                        request_exit()
                    end
                elseif sname == "START" and nes_widget then
                    nes_widget:key(key_code, 1)
                    sys.timerStart(function()
                        if nes_widget then
                            nes_widget:key(key_code, 0)
                        end
                    end, 80)
                elseif sname == "SELECT" and nes_widget then
                    nes_widget:key(key_code, 1)
                    sys.timerStart(function()
                        if nes_widget then
                            nes_widget:key(key_code, 0)
                        end
                    end, 80)
                end
            end
        else
            -- unknown 类型：降级为简单双边沿
            callback = function(val)
                if nes_widget then
                    nes_widget:key(key_code, val == 0 and 1 or 0)
                end
            end
        end

        gpio.setup(pin, callback, gpio.PULLUP, gpio.BOTH)
        table.insert(gpio_pins, pin)
        count = count + 1
        log.info("nes_emu", "GPIO", pin, "->", key_name, "(", key_type, ")")
    end
    log.info("nes_emu", "registered", count, "GPIO keys")
end

-- 释放所有实体按键 GPIO 中断
local function teardown_gpio_keys()
    for _, pin in ipairs(gpio_pins) do
        gpio.debounce(pin, 0)
        gpio.close(pin)
    end
    gpio_pins = {}
    log.info("nes_emu", "teardown GPIO keys done")
end

-- =========================================================
-- 游戏停止与清理
-- =========================================================

-- 停止当前运行的游戏（延迟执行，避免在 LVGL 回调中销毁父容器）
local function stop_game()
    sys.timerStart(function()
        teardown_gpio_keys()
        if nes_widget then
            nes_widget:destroy()
            nes_widget = nil
        end
        if game_ui then
            game_ui:destroy()
            game_ui = nil
        end
        if root_ui then
            root_ui:set_hidden(false)
        end
    end, 20)
end

-- 请求退出整个应用（关闭 exwin，延迟执行，防止重入）
local function request_exit()
    local wid = host_win_id
    host_win_id = nil  -- 提前置 nil，防止重入导致重复 close
    sys.timerStart(function()
        teardown_gpio_keys()
        if nes_widget then
            nes_widget:destroy()
            nes_widget = nil
        end
        if game_ui then
            game_ui:destroy()
            game_ui = nil
        end
        if root_ui then
            root_ui:destroy()
            root_ui = nil
        end
        if wid ~= nil then
            exwin.close(wid)
        end
    end, 20)
end

-- =========================================================
-- 游戏运行界面
-- =========================================================

-- 启动 NES ROM，进入游戏运行状态
local function launch_rom(path)
    log.info("nes_emu", "Loading ROM:", path)

    -- 隐藏游戏选择 UI（如果有）
    if root_ui then
        root_ui:set_hidden(true)
    end

    -- 创建游戏全屏容器
    game_ui = airui.container({
        x = 0, y = 0,
        w = SW, h = SH,
        color = 0x050508,
    })

    -- 顶栏背景
    airui.container({
        parent = game_ui,
        x = 0, y = 0, w = SW, h = HEADER_H,
        color = HEADER_BG,
        border_width = 0, radius = 0,
    })

    local exit_w = math.max(60, math.floor(SW * 0.15))
    local exit_h = math.max(28, math.floor(HEADER_H * 0.65))
    local exit_y = (HEADER_H - exit_h) // 2
    local btn_font = math.max(12, math.floor(exit_h * 0.47))

    -- Back 按钮：销毁 NES 组件并退出
    airui.button({
        parent = game_ui,
        text = "< Back",
        x = 4, y = exit_y, w = exit_w, h = exit_h,
        font_size = btn_font,
        style = { bg_color = 0xE74C3C, pressed_bg_color = 0xC0392B, radius = 8 },
        on_click = function()
            log.info("nes_emu", "user clicked Back")
            stop_game()
        end,
    })

    airui.label({
        parent = game_ui,
        text = "NES Emulator",
        x = exit_w + 8, y = exit_y, w = SW - exit_w - 16, h = exit_h,
        font_size = math.max(14, math.floor(exit_h * 0.58)), color = ACCENT,
    })

    -- 三区尺寸：以 NES 实际像素为基准，剩余空间给控制区
    local nes_w = 256 * NES_SCALE
    local nes_h = 240 * NES_SCALE
    local game_zone_h  = nes_h + 8                    -- NES 高度 + 上下各 4px 边距
    local ctrl_total_h = SH - HEADER_H - game_zone_h  -- 剩余全给控制区

    -- 游戏区：水平居中
    local nes_x = (SW - nes_w) // 2
    local nes_y = HEADER_H + (game_zone_h - nes_h) // 2
    log.info("nes_emu", "scale="..NES_SCALE.." nes_x="..nes_x.." nes_y="..nes_y
             .." nes_w="..nes_w.." nes_h="..nes_h.." ctrl_h="..ctrl_total_h)

    nes_widget = airui.nes({
        parent = game_ui,
        rom    = path,
        scale  = NES_SCALE,
        x      = nes_x,
        y      = nes_y,
    })

    if not nes_widget then
        log.error("nes_emu", "airui.nes create failed:", path)
        if game_ui then
            game_ui:destroy()
            game_ui = nil
        end
        return
    end

    -- 注册实体按键 GPIO（读取 project_config.nes_keys）
    setup_gpio_keys()

    -- -------------------------------------------------------
    -- 触控按键区布局
    -- -------------------------------------------------------
    local side_space = (SW - nes_w) // 2

    -- SEL/START 公共参数
    local bottom_space = SH - (nes_y + nes_h)
    local ss_h     = math.max(32, math.min(44, math.floor(bottom_space * 0.65) - 4))
    local ss_y     = SH - ss_h - 6
    local sel_w    = math.max(60, math.floor(SW * 0.13))
    local start_w  = math.max(72, math.floor(SW * 0.16))
    local ss_gap   = 12
    local ss_total = sel_w + start_w + ss_gap
    local sel_x    = (SW - ss_total) // 2
    local start_x  = sel_x + sel_w + ss_gap
    local font_small = math.max(13, math.floor(ss_h * 0.46))
    local ss_style = { bg_color = 0x3498DB, pressed_bg_color = 0x2980B9, radius = ss_h // 2 }

    local dpad_style = { bg_color = 0x2C4A6E, pressed_bg_color = 0x3D6288, radius = 10 }

    if side_space >= 150 then
        -- ---- 宽屏布局：方向键左侧，A/B 右侧 ----
        local game_mid_y = nes_y + nes_h // 2
        local dpad_btn  = math.max(56, math.min(90, math.floor(side_space * 0.28)))
        local dpad_gap  = math.max(14, math.floor(dpad_btn * 0.58))
        local font_dpad = math.max(16, math.floor(dpad_btn * 0.40))
        local dcx  = side_space // 2
        local dcy  = game_mid_y
        local up_x    = dcx - dpad_btn // 2
        local up_y    = dcy - dpad_gap - dpad_btn
        local down_x  = up_x
        local down_y  = dcy + dpad_gap
        local left_x  = dcx - dpad_gap - dpad_btn
        local left_y  = dcy - dpad_btn // 2
        local right_x = dcx + dpad_gap
        local ab_btn  = dpad_btn
        local font_ab = math.max(16, math.floor(ab_btn * 0.36))
        local rx_center = nes_x + nes_w + side_space // 2
        local ab_offset_x = math.floor(ab_btn * 0.45)
        local ab_offset_y = math.floor(ab_btn * 0.35)
        local ax = rx_center + ab_offset_x - ab_btn // 2
        local ay = game_mid_y - ab_offset_y - ab_btn
        local bx = rx_center - ab_offset_x - ab_btn // 2
        local by = game_mid_y + ab_offset_y

        airui.button({
            parent = game_ui, text = "^", x = up_x, y = up_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_UP, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_UP, 0) end,
        })
        airui.button({
            parent = game_ui, text = "v", x = down_x, y = down_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_DOWN, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_DOWN, 0) end,
        })
        airui.button({
            parent = game_ui, text = "<", x = left_x, y = left_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_LEFT, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_LEFT, 0) end,
        })
        airui.button({
            parent = game_ui, text = ">", x = right_x, y = left_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_RIGHT, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_RIGHT, 0) end,
        })
        airui.button({
            parent = game_ui, text = "B", x = bx, y = by, w = ab_btn, h = ab_btn,
            font_size = font_ab,
            style = { bg_color = 0x3498DB, pressed_bg_color = 0x5DADE2, radius = ab_btn // 2 },
            on_pressed  = function() nes_widget:key(airui.NES_KEY_B, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_B, 0) end,
        })
        airui.button({
            parent = game_ui, text = "A", x = ax, y = ay, w = ab_btn, h = ab_btn,
            font_size = font_ab,
            style = { bg_color = 0xE74C3C, pressed_bg_color = 0xF1948A, radius = ab_btn // 2 },
            on_pressed  = function() nes_widget:key(airui.NES_KEY_A, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_A, 0) end,
        })
    else
        -- ---- 窄屏布局：所有按键在 NES 下方 ----
        local ctrl_y      = HEADER_H + game_zone_h
        local ctrl_h      = SH - ctrl_y
        local main_ctrl_y = ctrl_y + 4
        local main_ctrl_h = ss_y - main_ctrl_y - 4
        local dpad_btn  = math.max(40, math.min(math.floor(SW * 0.13), math.floor(main_ctrl_h * 0.40)))
        local ab_btn    = math.max(44, math.min(math.floor(SW * 0.15), math.floor(main_ctrl_h * 0.42)))
        local font_dpad = math.max(13, math.floor(dpad_btn * 0.40))
        local font_ab   = math.max(15, math.floor(ab_btn * 0.36))
        local dpad_gap  = math.max(10, math.floor(dpad_btn * 0.55))
        local dcx     = math.floor(SW * 0.22)
        local dcy     = main_ctrl_y + main_ctrl_h // 2
        local up_x    = dcx - dpad_btn // 2
        local up_y    = dcy - dpad_gap - dpad_btn
        local down_x  = up_x
        local down_y  = dcy + dpad_gap
        local left_x  = dcx - dpad_gap - dpad_btn
        local left_y  = dcy - dpad_btn // 2
        local right_x = dcx + dpad_gap
        local acx = SW - ab_btn - math.floor(SW * 0.06)
        local bcx = acx - ab_btn - math.floor(SW * 0.05)
        local aby = main_ctrl_y + math.floor(main_ctrl_h * 0.18)
        local bcy = main_ctrl_y + math.floor(main_ctrl_h * 0.52)

        airui.button({
            parent = game_ui, text = "^", x = up_x, y = up_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_UP, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_UP, 0) end,
        })
        airui.button({
            parent = game_ui, text = "v", x = down_x, y = down_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_DOWN, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_DOWN, 0) end,
        })
        airui.button({
            parent = game_ui, text = "<", x = left_x, y = left_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_LEFT, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_LEFT, 0) end,
        })
        airui.button({
            parent = game_ui, text = ">", x = right_x, y = left_y, w = dpad_btn, h = dpad_btn,
            font_size = font_dpad, style = dpad_style,
            on_pressed  = function() nes_widget:key(airui.NES_KEY_RIGHT, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_RIGHT, 0) end,
        })
        airui.button({
            parent = game_ui, text = "B", x = bcx, y = bcy, w = ab_btn, h = ab_btn,
            font_size = font_ab,
            style = { bg_color = 0x3498DB, pressed_bg_color = 0x5DADE2, radius = ab_btn // 2 },
            on_pressed  = function() nes_widget:key(airui.NES_KEY_B, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_B, 0) end,
        })
        airui.button({
            parent = game_ui, text = "A", x = acx, y = aby, w = ab_btn, h = ab_btn,
            font_size = font_ab,
            style = { bg_color = 0xE74C3C, pressed_bg_color = 0xF1948A, radius = ab_btn // 2 },
            on_pressed  = function() nes_widget:key(airui.NES_KEY_A, 1) end,
            on_released = function() nes_widget:key(airui.NES_KEY_A, 0) end,
        })
    end

    airui.button({
        parent = game_ui, text = "SEL", x = sel_x, y = ss_y, w = sel_w, h = ss_h,
        font_size = font_small, style = ss_style,
        on_pressed  = function() nes_widget:key(airui.NES_KEY_SELECT, 1) end,
        on_released = function() nes_widget:key(airui.NES_KEY_SELECT, 0) end,
    })
    airui.button({
        parent = game_ui, text = "START", x = start_x, y = ss_y, w = start_w, h = ss_h,
        font_size = font_small, style = ss_style,
        on_pressed  = function() nes_widget:key(airui.NES_KEY_START, 1) end,
        on_released = function() nes_widget:key(airui.NES_KEY_START, 0) end,
    })

    log.info("nes_emu", "NES running:", path)
end

-- =========================================================
-- 错误提示界面（airui.nes 不可用时显示）
-- =========================================================

local function create_error_ui()
    local err_ui = airui.container({
        x = 0, y = 0, w = SW, h = SH,
        color = ROOT_BG,
    })
    airui.label({
        parent = err_ui,
        text = "airui.nes 不可用\nfirmware missing NES support",
        x = 20, y = SH // 2 - 80, w = SW - 40, h = 120,
        font_size = math.max(16, math.floor(SW * 0.046)), color = 0xFF4444,
    })
    airui.button({
        parent = err_ui,
        x = SW // 2 - 60, y = SH // 2 + 60, w = 120, h = 44,
        text = "返回",
        font_size = 20,
        style = {
            bg_color = 0x334155, pressed_bg_color = 0x475569,
            text_color = TEXT_COLOR, radius = 22,
        },
        on_click = function() request_exit() end,
    })
    root_ui = err_ui
end

-- =========================================================
-- exwin 回调
-- =========================================================

local function on_create()
    if not has_nes then
        create_error_ui()
        return
    end
    -- 直接启动指定 ROM，跳过选择页
    launch_rom(ROM_PATH)
end

local function on_destroy()
    -- 彻底清理：先释放 GPIO 和 NES 组件，再销毁 UI 容器
    teardown_gpio_keys()
    if nes_widget then
        nes_widget:destroy()
        nes_widget = nil
    end
    if game_ui then
        game_ui:destroy()
        game_ui = nil
    end
    if root_ui then
        root_ui:destroy()
        root_ui = nil
    end
    host_win_id = nil
end

local function on_lose_focus()  end
local function on_get_focus()   end

-- =========================================================
-- 入口：监听启动事件
-- =========================================================

local function open_handler()
    host_win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus  = on_get_focus,
    })
end

sys.subscribe("OPEN_NES_EMU_WIN", open_handler)

return nes_emulator
