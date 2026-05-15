--[[
@module  ecsend
@summary 寄存柜存件窗口模块
@version 4.4 (优化版 - 在稳定版本上微调美化)
@date    2026.05.12
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local density = _G.density_scale or 1

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    density = _G.density_scale or 1
end

local function create_ui()
    update_screen_size()

    -- 主容器 - 蓝白风格背景
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA,
        parent = airui.screen
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
        shadow = {
            offset_x = 0,
            offset_y = math.floor(3 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.12,
        }
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
            bg_color = 0xFFFFFF, pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })
    
    -- 标题
    airui.label({
        parent = header,
        text = "存件",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 左侧二维码区域
    local qr_x = math.floor(screen_w * 0.05)
    local qr_y = header_h + math.floor(screen_h * 0.08)
    local qr_w = math.floor(screen_w * 0.4)
    local qr_h = math.floor(screen_h * 0.72)
    
    local qr_container = airui.container({
        parent = main_container,
        x = qr_x,
        y = qr_y,
        w = qr_w,
        h = qr_h,
        color = 0xFFFFFF,
        radius = math.floor(12 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(4 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.1,
        }
    })

    -- 卡片顶部装饰条
    local card_header = airui.container({
        parent = qr_container,
        x = 0,
        y = 0,
        w = qr_w,
        h = math.floor(4 * density),
        color = 0x4A90E2,
        radius = {math.floor(12 * density), math.floor(12 * density), 0, 0},
    })

    -- 二维码标题
    airui.label({
        parent = qr_container,
        text = "扫描二维码",
        x = 0,
        y = math.floor(30 * density),
        w = qr_w,
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })

    -- 二维码
    airui.qrcode({
        parent = qr_container,
        x = math.floor((qr_w - math.floor(150 * density)) / 2),
        y = math.floor(70 * density),
        size = math.floor(150 * density),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码下方文字
    airui.label({
        parent = qr_container,
        text = "关注公众号",
        x = 0,
        y = math.floor(250 * density),
        w = qr_w,
        h = math.floor(20 * density),
        font_size = math.floor(15 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    airui.label({
        parent = qr_container,
        text = "开始存件流程",
        x = 0,
        y = math.floor(280 * density),
        w = qr_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })

    -- 右侧存件步骤区域 - 背景容器
    local steps_container = airui.container({
        parent = main_container,
        x = math.floor(screen_w * 0.48),
        y = qr_y,
        w = math.floor(screen_w * 0.47),
        h = qr_h,
        color = 0xFFFFFF,
        radius = math.floor(12 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(4 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.1,
        }
    })

    -- 卡片顶部装饰条
    local steps_card_header = airui.container({
        parent = steps_container,
        x = 0,
        y = 0,
        w = steps_container.w,
        h = math.floor(4 * density),
        color = 0x50C878,
        radius = {math.floor(12 * density), math.floor(12 * density), 0, 0},
    })

    -- 存件步骤标题 - 直接添加到main_container
    airui.label({
        parent = main_container,
        text = "存件步骤",
        x = math.floor(screen_w * 0.48) + math.floor(20 * density),
        y = qr_y + math.floor(25 * density),
        w = math.floor(screen_w * 0.43),
        h = math.floor(25 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 700,
    })

    -- 步骤列表
    local step_items = {
        "点击首页'存件'按钮",
        "扫描二维码关注公众号",
        "点击聊天框下方的寄件按钮",
        "选择箱子大小，付款",
        "等待柜门打开",
        "放入物品后关闭柜门",
        "记录取件码"
    }

    local step_y_start = qr_y + math.floor(65 * density)
    local step_height = math.floor(42 * density)
    local steps_x = math.floor(screen_w * 0.48)

    for i, step_text in ipairs(step_items) do
        -- 步骤序号圆圈
        local num_circle = airui.container({
            parent = main_container,
            x = steps_x + math.floor(20 * density),
            y = step_y_start + (i-1) * step_height,
            w = math.floor(24 * density),
            h = math.floor(24 * density),
            color = 0x4A90E2,
            radius = math.floor(12 * density),
        })

        airui.label({
            parent = num_circle,
            text = tostring(i),
            x = 0,
            y = math.floor((24 * density - 16 * density) / 2),
            w = math.floor(24 * density),
            h = math.floor(16 * density),
            font_size = math.floor(12 * density),
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 600,
        })

        -- 步骤文字 - 直接添加到main_container
        airui.label({
            parent = main_container,
            text = step_text,
            x = steps_x + math.floor(55 * density),
            y = step_y_start + (i-1) * step_height + math.floor(3 * density),
            w = math.floor(screen_w * 0.4),
            h = math.floor(20 * density),
            font_size = math.floor(13 * density),
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 500,
        })
    end

    -- 底部提示
    airui.label({
        parent = main_container,
        text = "提示：请确保柜门完全关闭后再离开",
        x = 0,
        y = screen_h - math.floor(35 * density),
        w = screen_w,
        h = math.floor(25 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 400,
    })
end

local function on_create()
    log.info("ecsend", "打开存件窗口")
    update_screen_size()
    create_ui()
end

local function on_destroy()
    log.info("ecsend", "关闭存件窗口")
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
    log.info("ecsend", "存件窗口获得焦点")
end

local function on_lose_focus()
    log.info("ecsend", "存件窗口失去焦点")
end

local function open()
    log.info("ecsend", "准备打开存件窗口")
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("ecsend", "存件窗口已打开，ID:", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_SEND_WIN", open)
log.info("ecsend", "订阅 OPEN_EXPRESS_SEND_WIN 消息")