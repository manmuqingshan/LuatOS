--[[
@module  settings_titlebar
@summary 设置页面标题栏共享组件
@version 1.0
@date    2026.05.12
@usage
local titlebar = require "settings_titlebar"
local _, th = titlebar.create(main_container, "设置", screen_w, function() exwin.close(window_id) end)
]]
local M = {}

local COLOR_PRIMARY = 0x007AFF
local COLOR_WHITE   = 0xFFFFFF

function M.create(parent, title, screen_w, on_back)
    local density = _G.density_scale or 1.0
    local bar_height = math.floor(60 * density)

    local title_bar = airui.container({
        parent = parent,
        x = 0, y = 0,
        w = screen_w, h = bar_height,
        color = COLOR_PRIMARY
    })

    local back_btn = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * density), h = math.floor(40 * density),
        color = COLOR_PRIMARY,
        on_click = on_back
    })
    airui.label({
        parent = back_btn,
        x = 0, y = math.floor(5 * density),
        w = math.floor(50 * density), h = math.floor(30 * density),
        text = "<",
        font_size = math.floor(28 * density),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题宽度自适应：根据字符数计算，取屏幕剩余宽度的较大值防止换行
    local title_char_count = 0
    for _ in string.gmatch(title, "[%z\1-\127\194-\244][\128-\191]*") do
        title_char_count = title_char_count + 1
    end
    local back_area = math.floor(70 * density)
    local title_max_w = screen_w - back_area - math.floor(10 * density)
    local title_calc_w = math.floor(title_char_count * 40 * density)
    local title_width = math.min(title_max_w, math.max(math.floor(100 * density), title_calc_w))

    airui.label({
        parent = title_bar,
        x = math.floor(60 * density), y = math.floor(10 * density),
        w = title_width, h = math.floor(40 * density),
        text = title,
        font_size = math.floor(32 * density),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    return title_bar, bar_height
end

return M
