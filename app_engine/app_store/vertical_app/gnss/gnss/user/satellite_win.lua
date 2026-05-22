--[[
@module  satellite_win
@summary 卫星信息页面模块
@version 1.0
@date    2026.05.21
@author  合宙技术
@usage
本模块为卫星信息页面，显示卫星的详细信息。
订阅"OPEN_SATELLITE_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local satellite_table
local exgnss = require("exgnss")

--[[
加载卫星数据
@local
@function load_satellite_data
@return nil
@usage
-- 加载并显示卫星数据
]]
local function load_satellite_data()
    if not exwin.is_active(win_id) then return end
    
    log.info("Satellite Win", "Loading satellite data...")
    
    local gsv = exgnss.gsv()
    log.info("Satellite Win", "exgnss.gsv() result:", json.encode(gsv))
    
    satellite_table:set_cell_text(0, 0, "编号")
    satellite_table:set_cell_text(0, 1, "类型")
    satellite_table:set_cell_text(0, 2, "信噪比")
    satellite_table:set_cell_text(0, 3, "方位角")
    satellite_table:set_cell_text(0, 4, "仰角")
    
    local function get_satellite_type(tp)
        local type_map = {[0] = "GPS", [1] = "BD", [2] = "GLON", [3] = "GAL", [4] = "QZSS"}
        return type_map[tp] or "Unknown"
    end
    
    if gsv and gsv.total_sats and gsv.total_sats > 0 and gsv.sats then
        log.info("Satellite Win", "Found " .. gsv.total_sats .. " satellites")
        for i, sat in ipairs(gsv.sats) do
            local row_index = i
            if row_index < satellite_table.rows then
                satellite_table:set_cell_text(row_index, 0, tostring(sat.nr))
                satellite_table:set_cell_text(row_index, 1, get_satellite_type(sat.tp))
                satellite_table:set_cell_text(row_index, 2, tostring(sat.snr) .. "dBm")
                satellite_table:set_cell_text(row_index, 3, tostring(sat.azimuth) .. "°")
                satellite_table:set_cell_text(row_index, 4, tostring(sat.elevation) .. "°")
                log.info("Satellite Win", "Added satellite to row " .. row_index)
            else
                log.warn("Satellite Win", "Not enough rows to display satellite " .. i)
            end
        end
    else
        log.warn("Satellite Win", "No satellite data found: " .. json.encode(gsv))
    end
end

--[[
创建窗口UI
@local
@function create_ui
@return nil
@usage
-- 内部调用，创建卫星信息页面的UI
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0x0f172a })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x1e293b })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = header, x = 10, y = 5, w = 70, h = 30, color = 0x38bdf8, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 标题
    airui.label({ parent = header, x = 90, y = 4, w = 280, h = 32, align = airui.TEXT_ALIGN_CENTER, text="卫星信息", font_size=24, color=0x38bdf8 })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0x1e293b })

    -- 卫星表格
    satellite_table = airui.table({ 
        parent = content, 
        x=10, 
        y=10, 
        w=460, 
        h=260, 
        rows = 9, 
        cols = 5, 
        col_width = {80, 100, 100, 80, 70}, 
        font_size = 12,
        border_color = 0x38bdf8,
    })
end

--[[
窗口创建回调
@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并加载卫星数据
]]
local function on_create()
    create_ui()
    
    local gsv = exgnss.gsv()
    
    satellite_table:set_cell_text(0, 0, "编号")
    satellite_table:set_cell_text(0, 1, "卫星类型")
    satellite_table:set_cell_text(0, 2, "信噪比")
    satellite_table:set_cell_text(0, 3, "方位角")
    satellite_table:set_cell_text(0, 4, "仰角")
    
    local function get_satellite_type(tp)
        local type_map = {[0] = "GPS", [1] = "BD", [2] = "GLON", [3] = "GAL", [4] = "QZSS"}
        return type_map[tp] or "Unknown"
    end
    
    if gsv and gsv.sats and #gsv.sats > 0 then
        for i = 1, math.min(#gsv.sats, 8) do
            local sat = gsv.sats[i]
            satellite_table:set_cell_text(i, 0, tostring(sat.nr))
            satellite_table:set_cell_text(i, 1, get_satellite_type(sat.tp))
            satellite_table:set_cell_text(i, 2, tostring(sat.snr) .. "dBm")
            satellite_table:set_cell_text(i, 3, tostring(sat.azimuth) .. "°")
            satellite_table:set_cell_text(i, 4, tostring(sat.elevation) .. "°")
        end
    else
        log.warn("Satellite Win", "No satellite data found")
    end
end

--[[
窗口销毁回调
@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
end

-- 窗口失去焦点回调
local function on_lose_focus()
end

-- 订阅打开卫星信息页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_SATELLITE_WIN", open_handler)

return {}
