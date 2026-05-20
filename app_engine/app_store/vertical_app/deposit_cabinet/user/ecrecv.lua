--[[
@module  ecrecv
@summary 寄存柜取件窗口模块
@version 8.6 (修复二维码和按钮显示问题)
@date    2026.05.12
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local keyboard = nil
local pickup_code_textarea = nil

-- 创建柜门已打开的弹窗
local function create_door_open_dialog()
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })

    local modal_content = airui.container({
        parent = modal,
        x = math.floor((screen_w - 300) / 2),
        y = math.floor((screen_h - 200) / 2),
        w = 300,
        h = 200,
        color = 0xFFFFFF,
        radius = 10,
    })

    airui.label({
        parent = modal_content,
        x = 0, y = 30,
        w = 300,
        h = 30,
        text = "柜门已打开",
        font_size = 20,
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    airui.label({
        parent = modal_content,
        x = 20,
        y = 70,
        w = 260,
        h = 40,
        text = "请及时取走您的物品",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = modal_content,
        x = 75,
        y = 130,
        w = 150,
        h = 45,
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = 22,
            font_size = 16,
            font_weight = 600,
        },
        on_click = function()
            modal:destroy()
            exwin.close(win_id)
        end
    })

    return modal
end

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

local function create_ui()
    update_screen_size()
    local density = _G.density_scale or 1
    
    -- 主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA
    })

    -- 键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 标题栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = math.floor(15 * density),
        y = math.floor((header_h - 35 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(35 * density),
        text = "返回",
        style = {
            bg_color = 0xFFFFFF, 
            pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2, 
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density), 
            font_weight = 500,
            border_width = 0,
        },
        on_click = function() 
            exwin.close(win_id) 
        end
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        text = "取件",
        color = 0xFFFFFF,
        font_size = math.floor(24 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域背景
    local content_bg = airui.container({
        parent = main_container,
        x = math.floor(20 * density), 
        y = header_h + math.floor(20 * density),
        w = screen_w - math.floor(40 * density), 
        h = screen_h - header_h - math.floor(100 * density),
        color = 0xFFFFFF,
        radius = math.floor(12 * density),
    })

    -- 取件码标题
    airui.label({
        parent = main_container,
        text = "取件码",
        x = math.floor(40 * density),
        y = header_h + math.floor(40 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    -- 取件码输入框
    pickup_code_textarea = airui.textarea({
        parent = main_container,
        x = math.floor(40 * density),
        y = header_h + math.floor(70 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(50 * density),
        placeholder = "请输入取件码",
        style = {
            bg_color = 0xF5F7FA,
            border_color = 0xE0E0E0,
            border_width = 1,
            radius = math.floor(8 * density),
            font_size = math.floor(16 * density),
            text_color = 0x333333,
        },
        keyboard = keyboard,
    })

    -- 二维码标题
    airui.label({
        parent = main_container,
        text = "扫描二维码",
        x = math.floor(40 * density),
        y = header_h + math.floor(140 * density),
        w = screen_w - math.floor(80 * density),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 二维码 - 直接添加到main_container
    airui.qrcode({
        parent = main_container,
        x = math.floor((screen_w - math.floor(150 * density)) / 2),
        y = header_h + math.floor(170 * density),
        size = math.floor(150 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码下方文字
    airui.label({
        parent = main_container,
        text = "关注公众号获取更多服务",
        x = 0,
        y = header_h + math.floor(330 * density),
        w = screen_w,
        h = math.floor(20 * density),
        font_size = math.floor(13 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })

    -- 确定按钮
    airui.button({
        parent = main_container,
        x = math.floor(20 * density),
        y = screen_h - math.floor(60 * density),
        w = math.floor((screen_w - math.floor(60 * density)) / 2),
        h = math.floor(50 * density),
        text = "取件",
        style = {
            bg_color = 0x4A90E2,
            pressed_bg_color = 0x3A80D2,
            text_color = 0xFFFFFF,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = function()
            create_door_open_dialog()
        end
    })

    -- 返回按钮
    airui.button({
        parent = main_container,
        x = math.floor((screen_w - math.floor(60 * density)) / 2) + math.floor(40 * density),
        y = screen_h - math.floor(60 * density),
        w = math.floor((screen_w - math.floor(60 * density)) / 2),
        h = math.floor(50 * density),
        text = "返回",
        style = {
            bg_color = 0xF0F0F0,
            pressed_bg_color = 0xE0E0E0,
            text_color = 0x666666,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_EXPRESS_RECEIVE_WIN", open_handler)