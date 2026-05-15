--[[
@module  vending_main_win
@summary 鲜啤售卖机主页面模块
@version 1.0
@date    5月12日
@author  杨乔杉
]]

local win_id = nil
local main_container = nil
local balance_label = nil
local price_label = nil
local selected_product = nil
local selected_volume = 500
local current_balance = 0
local payment_dialog = nil
local dispensing_dialog = nil
local info_labels = {}
local volume_buttons = {}
local product_buttons = {}
local beer_images = {}
local beer_section = nil
local center_section = nil
local current_beer_image = nil

local products = {
    { id = 1, name = "德式小麦", price = 19.9, stock = 50000, color = 0x4CAF50, img = "beer1.png" },
    { id = 2, name = "比利时白啤", price = 22.9, stock = 40000, color = 0x8BC34A, img = "beer2.png" },
    { id = 3, name = "经典白啤", price = 17.9, stock = 60000, color = 0xCDDC39, img = "beer3.png" },
    { id = 4, name = "黑啤", price = 24.9, stock = 35000, color = 0x607D8B, img = "beer4.png" },
}

local function calculate_price()
    if not selected_product then return 0 end
    return selected_product.price * (selected_volume / 500)
end

local function update_price_display()
    if price_label then
        price_label:set_text(string.format("%.2f", calculate_price()))
    end
end

local function update_balance_display()
    if balance_label then
        balance_label:set_text(string.format("%.2f", current_balance))
    end
end

local function update_info_display()
    if info_labels.product then
        info_labels.product:set_text("啤酒: " .. (selected_product and selected_product.name or "未选择"))
    end
    if info_labels.volume then
        info_labels.volume:set_text("容量: " .. selected_volume .. "mL")
    end
    if info_labels.price then
        info_labels.price:set_text("价格: " .. string.format("%.2f", calculate_price()))
    end
    if info_labels.stock then
        info_labels.stock:set_text("库存: " .. (selected_product and selected_product.stock or 0) .. " mL")
    end
end

local function switch_beer_image(index)
    if current_beer_image then
        if current_beer_image.set_src then
            current_beer_image:set_src("/luadb/beer" .. index .. ".png")
        else
            current_beer_image.src = "/luadb/beer" .. index .. ".png"
        end
    end
end

local function update_volume_buttons()
    local volumes = {500, 1500, 2500, 3500}
    for i, vol in ipairs(volumes) do
        if volume_buttons[i] then
            if volume_buttons[i].set_color then
                volume_buttons[i]:set_color(vol == selected_volume and 0x4CAF50 or 0x3D3D3D)
            elseif volume_buttons[i].set_property then
                volume_buttons[i]:set_property("color", vol == selected_volume and 0x4CAF50 or 0x3D3D3D)
            end
        end
    end
end

local function update_product_buttons()
    for i, prod in ipairs(products) do
        if product_buttons[i] then
            if product_buttons[i].set_color then
                product_buttons[i]:set_color(prod.id == selected_product.id and 0x4CAF50 or 0x3D3D3D)
            elseif product_buttons[i].set_property then
                product_buttons[i]:set_property("color", prod.id == selected_product.id and 0x4CAF50 or 0x3D3D3D)
            end
        end
    end
end

local function on_volume_click(volume)
    selected_volume = volume
    update_price_display()
    update_info_display()
    update_volume_buttons()
end

local function on_product_click(product)
    selected_product = product
    update_price_display()
    update_info_display()
    update_product_buttons()
    if current_beer_image then
        current_beer_image:destroy()
    end
    current_beer_image = airui.image({
        parent = center_section,
        x=65,
        y=15,
        w=160,
        h=110,
        src = "/luadb/" .. product.img,
        zoom = 256
    })
end

local function on_recharge_click(amount)
    current_balance = current_balance + amount
    update_balance_display()
    show_message("充值成功！已充值" .. amount, "success")
end

local function show_message(msg, type)
    local msg_color = type == "success" and 0x4CAF50 or (type == "error" and 0xF44336 or 0x2196F3)
    local msg_box = airui.container({ parent = main_container, x=80, y=300, w=320, h=80, color=0xFFFFFF, radius=10 })
    airui.label({ parent = msg_box, x=20, y=25, w=280, h=30, text=msg, font_size=20, color=msg_color, align=airui.TEXT_ALIGN_CENTER })
    sys.timerStart(function() msg_box:destroy() end, 2000)
end

local function close_payment_dialog()
    if payment_dialog then
        payment_dialog:destroy()
        payment_dialog = nil
    end
end

local dispensing_timer = nil

local function close_dispensing_dialog()
    if dispensing_timer then
        sys.timerStop(dispensing_timer)
        dispensing_timer = nil
    end
    if dispensing_dialog then
        dispensing_dialog:destroy()
        dispensing_dialog = nil
    end
end

local dispense_product

local function show_payment_dialog()
    if not selected_product then
        show_message("请选择啤酒类型", "error")
        return
    end
    
    local price = calculate_price()
    
    payment_dialog = airui.container({ parent = main_container, x=60, y=180, w=360, h=320, color=0xFFFFFF, radius=12 })
    
    airui.button({
        parent = payment_dialog,
        x=330,
        y=10,
        w=20,
        h=20,
        text = "x",
        font_size = 20,
        color = 0x999999,
        on_click = close_payment_dialog
    })
    
    airui.label({ parent = payment_dialog, x=0, y=30, w=360, h=30, text="请支付", font_size=22, color=0x333333, align=airui.TEXT_ALIGN_CENTER })
    
    airui.image({
        parent = payment_dialog,
        x=50,
        y=70,
        w=120,
        h=120,
        src = "/luadb/docs_qr.png",
        zoom = 256,
        opacity = 255
    })
    
    airui.label({ parent = payment_dialog, x=180, y=75, w=160, h=35, text=string.format("%.2f", price), font_size=32, color=0x333333 })
    airui.label({ parent = payment_dialog, x=180, y=115, w=160, h=20, text=string.format("%.2f/杯", price), font_size=16, color=0x999999 })
    airui.label({ parent = payment_dialog, x=180, y=140, w=160, h=40, text="请使用支付宝/微信扫码支付", font_size=14, color=0x666666 })
    
    airui.button({
        parent = payment_dialog,
        x=80,
        y=230,
        w=200,
        h=45,
        text = "支付完成",
        font_size = 22,
        color = 0x4CAF50,
        on_click = function()
            current_balance = current_balance + price
            update_balance_display()
            close_payment_dialog()
            dispense_product()
        end
    })
end

local function show_dispensing_dialog()
    dispensing_dialog = airui.container({ parent = main_container, x=0, y=0, w=480, h=800, color=0x1A1A1A })
    
    airui.label({ parent = dispensing_dialog, x=0, y=40, w=480, h=30, text=selected_product.name .. " | " .. selected_volume .. "mL", font_size=18, color=0x4CAF50, align=airui.TEXT_ALIGN_CENTER })
    
    local progress_ring = airui.container({ parent = dispensing_dialog, x=160, y=150, w=160, h=160, color=0x242424, radius=80 })
    airui.label({ parent = progress_ring, x=0, y=50, w=160, h=60, text="BEER", font_size=32, color=0x4CAF50, align=airui.TEXT_ALIGN_CENTER })
    
    local progress_label = airui.label({ parent = progress_ring, x=0, y=115, w=160, h=30, text="0%", font_size=22, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    
    airui.label({ parent = dispensing_dialog, x=60, y=350, w=100, h=25, text="气压", font_size=14, color=0x999999 })
    airui.label({ parent = dispensing_dialog, x=60, y=375, w=100, h=35, text="133kPa", font_size=24, color=0xFFFFFF })
    
    airui.label({ parent = dispensing_dialog, x=320, y=350, w=100, h=25, text="酒温", font_size=14, color=0x999999 })
    airui.label({ parent = dispensing_dialog, x=320, y=375, w=100, h=35, text="5°C", font_size=24, color=0xFFFFFF })
    
    airui.button({
        parent = dispensing_dialog,
        x=120,
        y=450,
        w=240,
        h=45,
        text = "结束打酒",
        font_size = 20,
        color = 0x64B5F6,
        on_click = function()
            local price = calculate_price()
            current_balance = current_balance - price
            update_balance_display()
            close_dispensing_dialog()
            show_message("打酒已取消，已退款", "error")
        end
    })
    
    local progress = 0
    dispensing_timer = sys.timerLoopStart(function()
        progress = progress + 2
        if progress > 100 then progress = 100 end
        progress_label:set_text(string.format("%d%%", progress))
        
        if progress >= 100 then
            close_dispensing_dialog()
            selected_product.stock = selected_product.stock - selected_volume
            local price = calculate_price()
            current_balance = current_balance - price
            update_balance_display()
            update_price_display()
            update_info_display()
            show_message("打酒成功！请取杯", "success")
            
            sys.publish("SALE_COMPLETED", {
                product_id = selected_product.id,
                product_name = selected_product.name,
                volume = selected_volume,
                price = price
            })
        end
    end, 80)
end

function dispense_product()
    if not selected_product then
        show_message("请选择啤酒类型", "error")
        return
    end
    
    if selected_product.stock < selected_volume then
        show_message("库存不足", "error")
        return
    end
    
    local price = calculate_price()
    
    if current_balance >= price then
        show_dispensing_dialog()
    else
        show_payment_dialog()
    end
end

local function create_ui()
    if main_container then return end
    
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0x1A1A1A })
    
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x242424 })
    airui.label({ parent = header, x=200, y=12, w=80, h=28, text="余额:", font_size=16, color=0xFFFFFF })
    balance_label = airui.label({ parent = header, x=255, y=12, w=80, h=28, text=string.format("%.2f", current_balance), font_size=16, color=0xFFFFFF })
    
    airui.label({ parent = main_container, x=20, y=60, w=120, h=25, text="容量选择", font_size=16, color=0x999999 })
    
    volume_buttons[1] = airui.button({
        parent = main_container,
        x=20,
        y=90,
        w=140,
        h=42,
        text="500mL",
        font_size=16,
        color=0x4CAF50,
        on_click = function() on_volume_click(500) end
    })
    volume_buttons[2] = airui.button({
        parent = main_container,
        x=20,
        y=137,
        w=140,
        h=42,
        text="1500mL",
        font_size=16,
        color=0x3D3D3D,
        on_click = function() on_volume_click(1500) end
    })
    volume_buttons[3] = airui.button({
        parent = main_container,
        x=20,
        y=184,
        w=140,
        h=42,
        text="2500mL",
        font_size=16,
        color=0x3D3D3D,
        on_click = function() on_volume_click(2500) end
    })
    volume_buttons[4] = airui.button({
        parent = main_container,
        x=20,
        y=231,
        w=140,
        h=42,
        text="3500mL",
        font_size=16,
        color=0x3D3D3D,
        on_click = function() on_volume_click(3500) end
    })
    
    center_section = airui.container({ parent = main_container, x=170, y=60, w=290, h=213, color=0x242424, radius=8 })
    
    current_beer_image = airui.image({
        parent = center_section,
        x=65,
        y=15,
        w=160,
        h=110,
        src = "/luadb/" .. products[1].img,
        zoom = 256
    })
    
    price_label = airui.label({ parent = center_section, x=20, y=135, w=120, h=30, text=string.format("%.2f", calculate_price()), font_size=26, color=0xFFFFFF, align=airui.TEXT_ALIGN_CENTER })
    airui.button({ 
        parent = center_section, 
        x=160, 
        y=140, 
        w=110, 
        h=32, 
        text="确认", 
        font_size=18, 
        color=0x64B5F6,
        on_click = dispense_product
    })
    airui.label({ parent = center_section, x=0, y=185, w=290, h=20, text="鲜啤现打，新鲜直达", font_size=12, color=0x999999, align=airui.TEXT_ALIGN_CENTER })
    
    local product_section = airui.container({ parent = main_container, x=20, y=315, w=440, h=70, color=0x242424, radius=8 })
    airui.label({ parent = product_section, x=10, y=10, w=120, h=20, text="啤酒类型", font_size=14, color=0x999999 })
    
    product_buttons[1] = airui.button({
        parent = product_section,
        x=15,
        y=35,
        w=95,
        h=30,
        text="德式小麦",
        font_size=14,
        color=0x4CAF50,
        on_click = function() on_product_click(products[1]) end
    })
    product_buttons[2] = airui.button({
        parent = product_section,
        x=120,
        y=35,
        w=95,
        h=30,
        text="比利时白啤",
        font_size=14,
        color=0x3D3D3D,
        on_click = function() on_product_click(products[2]) end
    })
    product_buttons[3] = airui.button({
        parent = product_section,
        x=225,
        y=35,
        w=95,
        h=30,
        text="经典白啤",
        font_size=14,
        color=0x3D3D3D,
        on_click = function() on_product_click(products[3]) end
    })
    product_buttons[4] = airui.button({
        parent = product_section,
        x=330,
        y=35,
        w=95,
        h=30,
        text="黑啤",
        font_size=14,
        color=0x3D3D3D,
        on_click = function() on_product_click(products[4]) end
    })
    
    local recharge_section = airui.container({ parent = main_container, x=20, y=400, w=440, h=55, color=0x242424, radius=8 })
    
    airui.button({
        parent = recharge_section,
        x=20,
        y=10,
        w=130,
        h=35,
        text="充值 50",
        font_size=16,
        color=0xFF9800,
        on_click = function() on_recharge_click(50) end
    })
    airui.button({
        parent = recharge_section,
        x=170,
        y=10,
        w=130,
        h=35,
        text="充值 100",
        font_size=16,
        color=0xFF9800,
        on_click = function() on_recharge_click(100) end
    })
    
    airui.button({ 
        parent = recharge_section, 
        x=320, 
        y=10, 
        w=100, 
        h=35, 
        text="库存管理", 
        font_size=14, 
        color=0x7E57C2,
        on_click = function()
            sys.publish("OPEN_INVENTORY_WIN") 
        end
    })
    
    local info_section = airui.container({ parent = main_container, x=20, y=470, w=440, h=280, color=0x242424, radius=8 })
    airui.label({ parent = info_section, x=10, y=10, w=120, h=20, text="当前选择", font_size=14, color=0x999999 })
    info_labels.product = airui.label({ parent = info_section, x=10, y=35, w=420, h=25, text="啤酒: " .. (selected_product and selected_product.name or "未选择"), font_size=16, color=0xFFFFFF })
    info_labels.volume = airui.label({ parent = info_section, x=10, y=65, w=420, h=25, text="容量: " .. selected_volume .. "mL", font_size=16, color=0xFFFFFF })
    info_labels.price = airui.label({ parent = info_section, x=10, y=95, w=420, h=25, text="价格: " .. string.format("%.2f", calculate_price()) .. "元", font_size=16, color=0xFFFFFF })
    info_labels.stock = airui.label({ parent = info_section, x=10, y=125, w=420, h=25, text="库存: " .. (selected_product and selected_product.stock or 0) .. " mL", font_size=16, color=0x4CAF50 })
    airui.label({ parent = info_section, x=10, y=160, w=420, h=30, text="鲜啤现打，新鲜直达", font_size=12, color=0x666666, align=airui.TEXT_ALIGN_CENTER })
    
    airui.button({ 
        parent = main_container, 
        x=20, 
        y=760, 
        w=440, 
        h=35, 
        text="退出应用", 
        font_size=16, 
        color=0xF44336,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
end

local function on_create()
    selected_product = products[1]
    selected_volume = 500
    current_balance = 0
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    if payment_dialog then
        payment_dialog:destroy()
        payment_dialog = nil
    end
    if dispensing_dialog then
        dispensing_dialog:destroy()
        dispensing_dialog = nil
    end
    balance_label = nil
    price_label = nil
    center_section = nil
    current_beer_image = nil
    selected_product = nil
    info_labels = {}
    volume_buttons = {}
    product_buttons = {}
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

sys.subscribe("VENDING_MAIN_WIN", open_handler)

return { open = open_handler }
