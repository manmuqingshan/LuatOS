--[[
@module  fskv_test_win
@summary fskv 读写删测试 320x480 固定分辨率
@version 1.0.4
@date    2026.05.13
]]

local window_id = nil
local main_container = nil
local W, H = 320, 480

-- sub tabs
local current_tab = "basic"
local tab_basic_btn, tab_adv_btn
local tab_content = nil

-- basic widgets
local key_input, value_input, result_label, keys_list

-- adv widgets
local tkey_input, skey_input, val2_input, result2_label, status_label

local C_PRIMARY = 0x007AFF
local C_DANGER  = 0xE63946
local C_SUCCESS = 0x4CAF50
local C_ACCENT  = 0xFF9800
local C_BG      = 0xF5F5F5
local C_CARD    = 0xFFFFFF
local C_TEXT    = 0x333333
local C_GRAY    = 0x757575
local C_DIV     = 0xE0E0E0
local C_WHITE   = 0xFFFFFF

-- ==================== fskv basic ====================

local function refresh_list()
    local keys = {}
    local iter = fskv.iter()
    while true do
        local k = fskv.next(iter)
        if not k then break end
        table.insert(keys, k)
    end
    if keys_list then
        keys_list:set_text(#keys == 0 and "(空)" or table.concat(keys, "\n"))
    end
    if result_label then
        local used, total = fskv.status()
        result_label:set_text(string.format("共%d条 已用%d/%dB", #keys, used or 0, total or 65536))
    end
end

local function do_write()
    local k = key_input:get_text()
    local v = value_input:get_text()
    if not k or k == "" then result_label:set_text("输入Key"); return end
    fskv.set(k, v)
    result_label:set_text(string.format("写入: %s=%s", k, v))
    refresh_list()
end

local function do_read()
    local k = key_input:get_text()
    if not k or k == "" then result_label:set_text("输入Key"); return end
    local v = fskv.get(k)
    if v ~= nil then
        value_input:set_text(tostring(v))
        result_label:set_text(string.format("读取: %s=%s", k, tostring(v)))
    else
        result_label:set_text(string.format("不存在: %s", k))
    end
end

local function do_delete()
    local k = key_input:get_text()
    if not k or k == "" then result_label:set_text("输入Key"); return end
    fskv.del(k)
    value_input:set_text("")
    result_label:set_text(string.format("已删除: %s", k))
    refresh_list()
end

local function do_clear_all()
    fskv.clear()
    result_label:set_text("已清空全部")
    refresh_list()
end

-- ==================== fskv advanced ====================

local function refresh_status()
    local used, total, kv_count = fskv.status()
    if status_label then
        status_label:set_text(string.format("已用%d/%dB %d对KV", used or 0, total or 65536, kv_count or 0))
    end
end

local function do_sett_write()
    local k = tkey_input:get_text()
    local sk = skey_input:get_text()
    local v = val2_input:get_text()
    if not k or k == "" then result2_label:set_text("输入TableKey"); return end
    if not sk or sk == "" then result2_label:set_text("输入SubKey"); return end
    fskv.sett(k, sk, v)
    result2_label:set_text(string.format("sett: %s.%s=%s", k, sk, v))
    refresh_status()
end

local function do_sett_read()
    local k = tkey_input:get_text()
    local sk = skey_input:get_text()
    if not k or k == "" or not sk or sk == "" then result2_label:set_text("输入TableKey和SubKey"); return end
    local v = fskv.get(k, sk)
    if v ~= nil then
        val2_input:set_text(tostring(v))
        result2_label:set_text(string.format("%s.%s=%s", k, sk, tostring(v)))
    else
        result2_label:set_text(string.format("不存在: %s.%s", k, sk))
    end
end

local function do_sett_delete()
    local k = tkey_input:get_text()
    local sk = skey_input:get_text()
    if not k or k == "" or not sk or sk == "" then result2_label:set_text("输入TableKey和SubKey"); return end
    fskv.sett(k, sk, nil)
    val2_input:set_text("")
    result2_label:set_text(string.format("已删除: %s.%s", k, sk))
    refresh_status()
end

local function do_get_table()
    local k = tkey_input:get_text()
    if not k or k == "" then result2_label:set_text("输入TableKey"); return end
    local v = fskv.get(k)
    if type(v) == "table" then
        result2_label:set_text(string.format("%s: %s", k, json.encode(v)))
    else
        result2_label:set_text(string.format("%s: %s", k, tostring(v or "nil")))
    end
end

local function do_status()
    refresh_status()
end

-- ==================== UI ====================

local function build_basic()
    local kb = airui.keyboard({ mode = "text", auto_hide = true, preview = true, w = W, h = 150, bg_color = C_CARD })
    local y = 4
    local lw = 46

    airui.label({ parent = tab_content, x = 8, y = y, w = lw, h = 30, text = "Key:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    key_input = airui.textarea({ parent = tab_content, x = 58, y = y, w = W - 66, h = 30, placeholder = "键名", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 34
    airui.label({ parent = tab_content, x = 8, y = y, w = lw, h = 30, text = "Val:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    value_input = airui.textarea({ parent = tab_content, x = 58, y = y, w = W - 66, h = 30, placeholder = "值", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 38

    local bh = 34
    local bw = 72
    airui.button({ parent = tab_content, x = 6, y = y, w = bw, h = bh, text = "写入", font_size = 15,
        style = { bg_color = C_PRIMARY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_write })
    airui.button({ parent = tab_content, x = 82, y = y, w = bw, h = bh, text = "查询", font_size = 15,
        style = { bg_color = C_SUCCESS, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_read })
    airui.button({ parent = tab_content, x = 158, y = y, w = bw, h = bh, text = "删除", font_size = 15,
        style = { bg_color = C_DANGER, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_delete })
    airui.button({ parent = tab_content, x = 234, y = y, w = bw, h = bh, text = "清空", font_size = 15,
        style = { bg_color = C_DANGER, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_clear_all })
    y = y + 42

    airui.container({ parent = tab_content, x = 8, y = y, w = W - 16, h = 1, color = C_DIV })
    y = y + 6
    result_label = airui.label({ parent = tab_content, x = 8, y = y, w = W - 16, h = 24, text = "就绪", font_size = 15, color = C_TEXT })
    y = y + 30
    airui.container({ parent = tab_content, x = 8, y = y, w = W - 16, h = 1, color = C_DIV })
    y = y + 6
    airui.label({ parent = tab_content, x = 8, y = y, w = W - 16, h = 22, text = "Key列表(sandbox前缀):", font_size = 13, color = C_GRAY })
    y = y + 24
    keys_list = airui.label({ parent = tab_content, x = 8, y = y, w = W - 16, h = H - 130 - y, text = "...", font_size = 13, color = C_TEXT })

    refresh_list()
end

local function build_adv()
    local kb = airui.keyboard({ mode = "text", auto_hide = true, preview = true, w = W, h = 150, bg_color = C_CARD })
    local y = 4
    local lw = 52

    airui.label({ parent = tab_content, x = 8, y = y, w = lw, h = 30, text = "TKey:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    tkey_input = airui.textarea({ parent = tab_content, x = 64, y = y, w = W - 72, h = 30, placeholder = "表名", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 34
    airui.label({ parent = tab_content, x = 8, y = y, w = lw, h = 30, text = "SKey:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    skey_input = airui.textarea({ parent = tab_content, x = 64, y = y, w = W - 72, h = 30, placeholder = "子键", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 34
    airui.label({ parent = tab_content, x = 8, y = y, w = lw, h = 30, text = "Val:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    val2_input = airui.textarea({ parent = tab_content, x = 64, y = y, w = W - 72, h = 30, placeholder = "值", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 38

    local bh = 34
    local bw = 72
    airui.button({ parent = tab_content, x = 6, y = y, w = bw, h = bh, text = "sett写", font_size = 14,
        style = { bg_color = C_PRIMARY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_sett_write })
    airui.button({ parent = tab_content, x = 82, y = y, w = bw, h = bh, text = "get查", font_size = 14,
        style = { bg_color = C_SUCCESS, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_sett_read })
    airui.button({ parent = tab_content, x = 158, y = y, w = bw, h = bh, text = "删子键", font_size = 14,
        style = { bg_color = C_DANGER, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_sett_delete })
    airui.button({ parent = tab_content, x = 234, y = y, w = bw, h = bh, text = "取整表", font_size = 14,
        style = { bg_color = C_ACCENT, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_get_table })
    y = y + 40

    airui.button({ parent = tab_content, x = 8, y = y, w = W - 16, h = 34, text = "fskv.status()", font_size = 15,
        style = { bg_color = C_GRAY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_status })
    y = y + 40
    status_label = airui.label({ parent = tab_content, x = 8, y = y, w = W - 16, h = 24, text = "未查询", font_size = 15, color = C_TEXT })
    y = y + 30
    airui.container({ parent = tab_content, x = 8, y = y, w = W - 16, h = 1, color = C_DIV })
    y = y + 6
    result2_label = airui.label({ parent = tab_content, x = 8, y = y, w = W - 16, h = H - 130 - y, text = "就绪", font_size = 14, color = C_TEXT })

    refresh_status()
end

local function switch_tab(tab)
    current_tab = tab
    if tab_basic_btn then
        tab_basic_btn:set_style({
            bg_color = (tab == "basic") and C_PRIMARY or C_DIV,
            text_color = (tab == "basic") and C_WHITE or C_TEXT,
            radius = 7, border_width = 0
        })
    end
    if tab_adv_btn then
        tab_adv_btn:set_style({
            bg_color = (tab == "adv") and C_PRIMARY or C_DIV,
            text_color = (tab == "adv") and C_WHITE or C_TEXT,
            radius = 7, border_width = 0
        })
    end
    if tab_content then tab_content:destroy(); tab_content = nil end
    key_input = nil; value_input = nil; result_label = nil; keys_list = nil
    tkey_input = nil; skey_input = nil; val2_input = nil; result2_label = nil; status_label = nil
    tab_content = airui.container({ parent = main_container, x = 0, y = 114, w = W, h = H - 114, color = C_BG })
    if tab == "basic" then build_basic() else build_adv() end
end

-- ==================== build_ui ====================

local function build_ui()
    main_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = W, h = H, color = C_BG
    })

    -- title bar
    local th = 44
    local tb = airui.container({ parent = main_container, x = 0, y = 0, w = W, h = th, color = C_PRIMARY })
    airui.label({ parent = tb, x = 0, y = 6, w = W, h = 36, text = "fskv 测试", font_size = 20, color = C_WHITE, align = airui.TEXT_ALIGN_CENTER })
    airui.button({ parent = tb, x = 4, y = 6, w = 36, h = 32, text = "X", font_size = 17,
        style = { bg_color = C_PRIMARY, text_color = C_WHITE, radius = 6, border_width = 0 },
        on_click = function() exwin.close(window_id) end })

    -- tab bar
    local tabh = 36
    local tabb = airui.container({ parent = main_container, x = 0, y = th, w = W, h = tabh, color = C_CARD })
    local tw = 140
    tab_basic_btn = airui.button({
        parent = tabb, x = 10, y = 3, w = tw, h = tabh - 6,
        text = "set/get/del", font_size = 16,
        style = { bg_color = C_PRIMARY, text_color = C_WHITE, radius = 7, border_width = 0 },
        on_click = function() switch_tab("basic") end
    })
    tab_adv_btn = airui.button({
        parent = tabb, x = 160, y = 3, w = tw, h = tabh - 6,
        text = "sett/status", font_size = 16,
        style = { bg_color = C_DIV, text_color = C_TEXT, radius = 7, border_width = 0 },
        on_click = function() switch_tab("adv") end
    })

    -- info line
    local iy = th + tabh
    airui.container({ parent = main_container, x = 0, y = iy, w = W, h = 34, color = C_BG })
    airui.label({ parent = main_container, x = 8, y = iy + 4, w = W - 16, h = 26,
        text = "芯片内置Flash 64KB | key自动加应用前缀", font_size = 12, color = C_GRAY })

    -- content
    local cy = iy + 34
    tab_content = airui.container({ parent = main_container, x = 0, y = cy, w = W, h = H - cy, color = C_BG })
    build_basic()
end

local function on_create()
    build_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create    = on_create,
        on_destroy   = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_FSKV_TEST_WIN", open_handler)
