--[[
@module  inventory_win
@summary 管理后台页面模块
@version 1.0
@date    2026.05.12
@author  杨乔杉
]]

local win_id = nil
local main_container, content, sidebar

local brightness_level = 80
local brightness_label = nil

local products = {
    { id = 1, name = "德式小麦", price = 19.9, stock = 50000, sold = 0, sales = 0 },
    { id = 2, name = "比利时白啤", price = 22.9, stock = 40000, sold = 0, sales = 0 },
    { id = 3, name = "经典白啤", price = 17.9, stock = 60000, sold = 0, sales = 0 },
    { id = 4, name = "黑啤", price = 24.9, stock = 35000, sold = 0, sales = 0 },
}

local menus = {
    { id = "stats", name = "售酒统计" },
    { id = "pressure", name = "气瓶气压检测" },
    { id = "function", name = "功能检测" },
    { id = "settings", name = "系统设置" },
}

local active_menu = "stats"

local function show_message(msg, type)
    local msg_color = type == "success" and 0x4CAF50 or (type == "error" and 0xF44336 or 0x2196F3)
    local msg_box = airui.container({ parent = main_container, x=200, y=350, w=280, h=80, color=0xFFFFFF, radius=10 })
    airui.label({ parent = msg_box, x=20, y=25, w=240, h=30, text=msg, font_size=20, color=msg_color, align=airui.TEXT_ALIGN_CENTER })
    sys.timerStart(function() msg_box:destroy() end, 2000)
end

local function update_brightness_display()
    if brightness_label then
        brightness_label:set_text(brightness_level .. "%")
    end
end

local function create_stats_page()
    local stats_content = airui.container({ parent = content, x=0, y=0, w=360, h=740, color=0x242424 })
    
    airui.label({ parent = stats_content, x=10, y=15, w=340, h=30, text="售酒信息统计", font_size=20, color=0x4CAF50 })
    
    local y = 60
    for i, product in ipairs(products) do
        local card = airui.container({ parent = stats_content, x=15 + ((i-1) % 2)*170, y=y + math.floor((i-1)/2)*125, w=160, h=115, color=0x323232, radius=8 })
        
        airui.label({ parent = card, x=10, y=10, w=140, h=25, text=product.name, font_size=16, color=0xFFFFFF })
        
        airui.label({ parent = card, x=10, y=38, w=60, h=20, text="库存", font_size=12, color=0x999999 })
        airui.label({ parent = card, x=70, y=38, w=70, h=20, text=string.format("%dmL", product.stock), font_size=12, color=0xFF9800 })
        
        airui.label({ parent = card, x=10, y=60, w=60, h=20, text="已售", font_size=12, color=0x999999 })
        airui.label({ parent = card, x=70, y=60, w=70, h=20, text=string.format("%dmL", product.sold), font_size=12, color=0x4CAF50 })
        
        airui.label({ parent = card, x=10, y=82, w=60, h=20, text="销售额", font_size=12, color=0x999999 })
        airui.label({ parent = card, x=70, y=82, w=75, h=20, text=string.format("%.0f元", product.sales), font_size=12, color=0x64B5F6 })
    end
    
    local total_sales = 0
    local total_sold = 0
    local total_stock = 0
    for _, p in ipairs(products) do
        total_sales = total_sales + p.sales
        total_sold = total_sold + p.sold
        total_stock = total_stock + p.stock
    end
    
    local summary_card = airui.container({ parent = stats_content, x=15, y=320, w=330, h=90, color=0x323232, radius=8 })
    airui.label({ parent = summary_card, x=15, y=10, w=100, h=25, text="总计", font_size=16, color=0xFFFFFF })
    airui.label({ parent = summary_card, x=15, y=40, w=300, h=25, text=string.format("%.2f元", total_sales), font_size=18, color=0x4CAF50 })
    airui.label({ parent = summary_card, x=15, y=70, w=300, h=20, text=string.format("已售: %dmL | 库存: %dmL", total_sold, total_stock), font_size=12, color=0x999999 })
end

local function create_pressure_page()
    local pressure_content = airui.container({ parent = content, x=0, y=0, w=360, h=740, color=0x242424 })
    
    airui.label({ parent = pressure_content, x=10, y=15, w=340, h=30, text="气瓶气压检测", font_size=20, color=0x4CAF50 })
    
    local current_pressure_card = airui.container({ parent = pressure_content, x=15, y=60, w=330, h=80, color=0x323232, radius=8 })
    airui.label({ parent = current_pressure_card, x=15, y=15, w=120, h=25, text="当前气压", font_size=16, color=0x999999 })
    airui.label({ parent = current_pressure_card, x=140, y=15, w=120, h=30, text="130Kpa", font_size=24, color=0xFFFFFF })
    airui.button({
        parent = current_pressure_card,
        x=270,
        y=15,
        w=50,
        h=30,
        text = "正常",
        font_size = 14,
        color = 0x4CAF50
    })
    
    local gauge_card = airui.container({ parent = pressure_content, x=15, y=145, w=160, h=155, color=0x323232, radius=8 })
    airui.label({ parent = gauge_card, x=10, y=8, w=140, h=22, text="调试标准", font_size=14, color=0x999999 })
    airui.label({ parent = gauge_card, x=10, y=35, w=140, h=20, text="低压区", font_size=13, color=0xF44336, align=airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = gauge_card, x=10, y=55, w=140, h=16, text="< 100 Kpa", font_size=11, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = gauge_card, x=10, y=76, w=140, h=20, text="正常压区", font_size=13, color=0x4CAF50, align=airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = gauge_card, x=10, y=96, w=140, h=16, text="100-150 Kpa", font_size=11, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = gauge_card, x=10, y=117, w=140, h=20, text="高压区", font_size=13, color=0xFF9800, align=airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = gauge_card, x=10, y=137, w=140, h=16, text="> 150 Kpa", font_size=11, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    
    local steps_card = airui.container({ parent = pressure_content, x=185, y=145, w=160, h=145, color=0x323232, radius=8 })
    airui.label({ parent = steps_card, x=10, y=8, w=140, h=22, text="调试步骤", font_size=14, color=0x999999 })
    airui.label({ parent = steps_card, x=10, y=35, w=140, h=100, text="1.顺时针打开气瓶阀门\n2.调整至135Kpa\n3.点击开始检测", font_size=13, color=0xEEEEEE })
    
    airui.button({
        parent = pressure_content,
        x=60,
        y=300,
        w=240,
        h=45,
        text = "开始检测",
        font_size = 18,
        color = 0x64B5F6,
        on_click = function()
            show_message("正在检测气压...", "info")
            sys.timerStart(function()
                show_message("气瓶气压检测完成", "success")
            end, 2000)
        end
    })
end

local function create_function_page()
    local func_content = airui.container({ parent = content, x=0, y=0, w=360, h=740, color=0x242424 })
    
    airui.label({ parent = func_content, x=10, y=15, w=340, h=30, text="请完成以下准备后再开始检测", font_size=16, color=0x4CAF50 })
    
    local prepare_items = {
        { name = "气瓶已打开" },
        { name = "气压值正常" },
        { name = "酒桶已安装" },
    }
    
    for i, item in ipairs(prepare_items) do
        local card = airui.container({ parent = func_content, x=15 + (i-1)*110, y=60, w=100, h=100, color=0x323232, radius=8 })
        airui.label({ parent = card, x=15, y=15, w=70, h=40, text="✓", font_size=36, color=0x4CAF50, align=airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = card, x=5, y=60, w=90, h=30, text=item.name, font_size=12, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    end
    
    airui.button({
        parent = func_content,
        x=60,
        y=180,
        w=240,
        h=45,
        text = "开始检测",
        font_size = 18,
        color = 0x64B5F6,
        on_click = function()
            show_message("正在进行功能检测...", "info")
            sys.timerStart(function()
                show_message("检测完成，所有设备正常", "success")
            end, 3000)
        end
    })
    
    local functions = {
        { name = "打酒泵", status = "正常" },
        { name = "制冷系统", status = "正常" },
        { name = "液位传感器", status = "正常" },
        { name = "温控器", status = "正常" },
        { name = "电磁阀1", status = "正常" },
        { name = "电磁阀2", status = "正常" },
        { name = "显示屏", status = "正常" },
        { name = "扫码模块", status = "正常" },
    }
    
    airui.label({ parent = func_content, x=15, y=250, w=100, h=25, text="设备状态", font_size=16, color=0x999999 })
    
    local y = 280
    for i, func in ipairs(functions) do
        local row = airui.container({ parent = func_content, x=15, y=y, w=330, h=40, color=0x323232, radius=5 })
        airui.label({ parent = row, x=15, y=8, w=120, h=25, text=func.name, font_size=14, color=0xFFFFFF })
        airui.label({ parent = row, x=280, y=8, w=40, h=25, text=func.status, font_size=12, color=0x4CAF50 })
        y = y + 45
    end
end

local auto_lock_enabled = true
local voice_enabled = true
local standby_time = "1分钟"
local settings_buttons = {}

local function on_toggle_click(key, enabled, msg_on, msg_off)
    enabled = not enabled
    settings_buttons[key]:set_text(enabled and "开" or "关")
    settings_buttons[key]:set_color(enabled and 0x4CAF50 or 0xF44336)
    show_message((enabled and msg_on or msg_off), enabled and "success" or "info")
    return enabled
end

local function on_brightness_adjust(delta)
    if brightness_level > 20 and delta < 0 or brightness_level < 100 and delta > 0 then
        brightness_level = brightness_level + delta
        update_brightness_display()
        show_message("亮度已调整为" .. brightness_level .. "%", "success")
    end
end

local function on_standby_click(time)
    standby_time = time
    show_message("待机时间已设置为" .. time, "success")
end

local function create_settings_page()
    local settings_content = airui.container({ parent = content, x=0, y=0, w=360, h=740, color=0x242424 })
    
    airui.label({ parent = settings_content, x=10, y=15, w=340, h=30, text="系统设置", font_size=20, color=0x4CAF50 })
    
    local y = 60
    
    local auto_lock_row = airui.container({ parent = settings_content, x=15, y=y, w=330, h=45, color=0x323232, radius=5 })
    airui.label({ parent = auto_lock_row, x=15, y=10, w=120, h=25, text="自动锁屏", font_size=16, color=0xFFFFFF })
    settings_buttons["auto_lock"] = airui.button({
        parent = auto_lock_row,
        x=270,
        y=5,
        w=50,
        h=30,
        text = auto_lock_enabled and "开" or "关",
        font_size = 14,
        color = auto_lock_enabled and 0x4CAF50 or 0xF44336,
        on_click = function()
            auto_lock_enabled = on_toggle_click("auto_lock", auto_lock_enabled, "自动锁屏已开启", "自动锁屏已关闭")
        end
    })
    y = y + 50
    
    local voice_row = airui.container({ parent = settings_content, x=15, y=y, w=330, h=45, color=0x323232, radius=5 })
    airui.label({ parent = voice_row, x=15, y=10, w=120, h=25, text="语音提示", font_size=16, color=0xFFFFFF })
    settings_buttons["voice"] = airui.button({
        parent = voice_row,
        x=270,
        y=5,
        w=50,
        h=30,
        text = voice_enabled and "开" or "关",
        font_size = 14,
        color = voice_enabled and 0x4CAF50 or 0xF44336,
        on_click = function()
            voice_enabled = on_toggle_click("voice", voice_enabled, "语音提示已开启", "语音提示已关闭")
        end
    })
    y = y + 50
    
    local brightness_row = airui.container({ parent = settings_content, x=15, y=y, w=330, h=50, color=0x323232, radius=5 })
    airui.label({ parent = brightness_row, x=15, y=12, w=120, h=25, text="亮度调节", font_size=16, color=0xFFFFFF })
    
    settings_buttons["brightness_minus"] = airui.button({
        parent = brightness_row,
        x=135,
        y=10,
        w=35,
        h=28,
        text = "-",
        font_size = 20,
        color = 0x64B5F6,
        on_click = function()
            on_brightness_adjust(-10)
        end
    })
    
    brightness_label = airui.label({ parent = brightness_row, x=175, y=12, w=50, h=25, text=brightness_level .. "%", font_size=14, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    
    settings_buttons["brightness_plus"] = airui.button({
        parent = brightness_row,
        x=230,
        y=10,
        w=35,
        h=28,
        text = "+",
        font_size = 20,
        color = 0x64B5F6,
        on_click = function()
            on_brightness_adjust(10)
        end
    })
    
    local brightness_bar = airui.container({ parent = brightness_row, x=270, y=15, w=50, h=15, color=0x4CAF50, radius=8 })
    settings_buttons["brightness_bar"] = airui.container({ parent = brightness_bar, x=0, y=0, w=brightness_level * 0.5, h=15, color=0x81C784, radius=8 })
    y = y + 55
    
    local standby_row = airui.container({ parent = settings_content, x=15, y=y, w=330, h=45, color=0x323232, radius=5 })
    airui.label({ parent = standby_row, x=15, y=10, w=120, h=25, text="待机时间", font_size=16, color=0xFFFFFF })
    
    settings_buttons["standby1"] = airui.button({
        parent = standby_row,
        x=165,
        y=8,
        w=60,
        h=28,
        text = "1分钟",
        font_size = 14,
        color = standby_time == "1分钟" and 0x4CAF50 or 0x3D3D3D,
        on_click = function()
            on_standby_click("1分钟")
        end
    })
    
    settings_buttons["standby2"] = airui.button({
        parent = standby_row,
        x=230,
        y=8,
        w=50,
        h=28,
        text = "3分钟",
        font_size = 14,
        color = standby_time == "3分钟" and 0x4CAF50 or 0x3D3D3D,
        on_click = function()
            on_standby_click("3分钟")
        end
    })
    
    settings_buttons["standby3"] = airui.button({
        parent = standby_row,
        x=285,
        y=8,
        w=40,
        h=28,
        text = "5分钟",
        font_size = 14,
        color = standby_time == "5分钟" and 0x4CAF50 or 0x3D3D3D,
        on_click = function()
            on_standby_click("5分钟")
        end
    })
    y = y + 50
    
    airui.button({
        parent = settings_content,
        x=50,
        y=y+20,
        w=260,
        h=45,
        text = "恢复出厂设置",
        font_size = 18,
        color = 0xF44336,
        on_click = function()
            local confirm_dialog = airui.container({ parent = settings_content, x=30, y=200, w=300, h=180, color=0xFFFFFF, radius=12 })
            airui.label({ parent = confirm_dialog, x=0, y=25, w=300, h=30, text="确认恢复出厂设置？", font_size=18, color=0x333333, align=airui.TEXT_ALIGN_CENTER })
            airui.label({ parent = confirm_dialog, x=30, y=60, w=240, h=40, text="此操作将清除所有数据，包括库存、销售记录等，且无法恢复。", font_size=12, color=0x666666, align=airui.TEXT_ALIGN_CENTER })
            
            airui.button({
                parent = confirm_dialog,
                x=20,
                y=115,
                w=120,
                h=40,
                text = "取消",
                font_size = 16,
                color = 0x999999,
                on_click = function() 
                    confirm_dialog:destroy() 
                end
            })
            
            airui.button({
                parent = confirm_dialog,
                x=160,
                y=115,
                w=120,
                h=40,
                text = "确认",
                font_size = 16,
                color = 0xF44336,
                on_click = function()
                    confirm_dialog:destroy()
                    show_message("正在恢复出厂设置...", "info")
                    sys.timerStart(function()
                        show_message("恢复出厂设置完成", "success")
                    end, 2000)
                end
            })
        end
    })
    
    airui.button({
        parent = settings_content,
        x=50,
        y=480,
        w=260,
        h=45,
        text = "重启设备",
        font_size = 18,
        color = 0xFF9800,
        on_click = function()
            show_message("设备即将重启...", "info")
        end
    })
    
    airui.button({
        parent = settings_content,
        x=50,
        y=540,
        w=260,
        h=45,
        text = "退出APP",
        font_size = 18,
        color = 0xF44336,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
end

local function on_menu_click(menu_id)
    active_menu = menu_id
    if content then
        content:destroy()
        content = nil
    end
    
    content = airui.container({ parent = main_container, x=120, y=0, w=360, h=800, color=0x242424 })
    
    if active_menu == "stats" then
        create_stats_page()
    elseif active_menu == "pressure" then
        create_pressure_page()
    elseif active_menu == "function" then
        create_function_page()
    elseif active_menu == "settings" then
        create_settings_page()
    else
        create_stats_page()
    end
end

local function set_menu_active(menu_id)
    active_menu = menu_id
end



local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0x1A1A1A })
    
    sidebar = airui.container({ parent = main_container, x=0, y=0, w=120, h=800, color=0x242424 })
    
    airui.button({ 
        parent = sidebar,
        x=10,
        y=15,
        w=100,
        h=40,
        text = "← 返回",
        font_size = 16,
        color = 0x5E35B1,
        on_click = function() 
            if win_id then exwin.close(win_id) end 
        end
    })
    
    airui.button({
        parent = sidebar,
        x=10,
        y=70,
        w=100,
        h=50,
        text = "售酒统计",
        font_size = 16,
        color = 0x4CAF50,
        on_click = function()
            on_menu_click("stats")
        end
    })
    
    airui.button({
        parent = sidebar,
        x=10,
        y=135,
        w=100,
        h=50,
        text = "气瓶气压检测",
        font_size = 16,
        color = 0x3D3D3D,
        on_click = function()
            on_menu_click("pressure")
        end
    })
    
    airui.button({
        parent = sidebar,
        x=10,
        y=200,
        w=100,
        h=50,
        text = "功能检测",
        font_size = 16,
        color = 0x3D3D3D,
        on_click = function()
            on_menu_click("function")
        end
    })
    
    airui.button({
        parent = sidebar,
        x=10,
        y=265,
        w=100,
        h=50,
        text = "系统设置",
        font_size = 16,
        color = 0x3D3D3D,
        on_click = function()
            on_menu_click("settings")
        end
    })
    
    content = airui.container({ parent = main_container, x=120, y=0, w=360, h=800, color=0x242424 })
    create_stats_page()
end

local function on_create()
    active_menu = "stats"
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    sidebar = nil
    win_id = nil
end

local function open_handler()
    if win_id then exwin.close(win_id) end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
end

sys.subscribe("SALE_COMPLETED", function(data)
    for _, product in ipairs(products) do
        if product.id == data.product_id then
            product.sold = product.sold + data.volume
            product.sales = product.sales + data.price
            product.stock = product.stock - data.volume
            break
        end
    end
    
    if active_menu == "stats" and content then
        refresh_content()
    end
end)

sys.subscribe("OPEN_INVENTORY_WIN", open_handler)