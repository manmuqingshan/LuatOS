--[[
@module  fs_test_win
@summary 多存储文件IO测试 320x480 固定分辨率
@version 1.0.0
@date    2026.05.13
]]

local window_id = nil
local main_container = nil
local W, H = 320, 480

local path_dropdown, name_input, content_input, result_label
local current_storage = "/ram/"
local storage_paths = { "/ram/", "/sd/", "/little_flash/", "/" }
local storage_labels = { "RAM(/ram/)", "TF卡(/sd/)", "外挂Flash", "内置Flash(/)" }

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

-- ==================== 文件操作 ====================

local function fp_join()
    local fn = name_input:get_text()
    if not fn or fn == "" then result_label:set_text("输入文件名"); return nil end
    return current_storage .. fn
end

local function do_write()
    local fp = fp_join() if not fp then return end
    local ct = content_input:get_text() or ""
    local ok = io.writeFile(fp, ct)
    result_label:set_text(ok and string.format("写入: %s (%dB)", fp, #ct) or string.format("写入失败: %s", fp))
end

local function do_read()
    local fp = fp_join() if not fp then return end
    local data = io.readFile(fp)
    if data then
        content_input:set_text(data)
        result_label:set_text(string.format("读取: %s (%dB)", fp, #data))
    else
        content_input:set_text("")
        result_label:set_text(string.format("不存在: %s", fp))
    end
end

local function do_delete()
    local fp = fp_join() if not fp then return end
    os.remove(fp)
    result_label:set_text(string.format("已删除: %s", fp))
end

local function do_mkdir()
    local fn = name_input:get_text()
    if not fn or fn == "" then result_label:set_text("输入目录名"); return end
    local dir = current_storage .. fn .. "/"
    local ok = io.mkdir(dir)
    result_label:set_text(ok and string.format("创建目录: %s", dir) or string.format("创建失败: %s", dir))
end

local function do_list()
    local ok, list = io.lsdir(current_storage .. "", 50, 0)
    if ok and list then
        local lines = {}
        for _, item in ipairs(list) do
            table.insert(lines, ((item.type == 1) and "[D] " or "[F] ") .. item.name)
        end
        result_label:set_text(#lines > 0 and table.concat(lines, "\n") or "(空目录)")
    else
        result_label:set_text("无法读取: " .. current_storage)
    end
end

local function do_file_size()
    local fp = fp_join() if not fp then return end
    local sz = io.fileSize(fp)
    result_label:set_text(sz and string.format("大小: %s = %d B", fp, sz) or string.format("不存在: %s", fp))
end

local function do_exists()
    local fp = fp_join() if not fp then return end
    local ok = io.exists(fp)
    result_label:set_text(ok and string.format("存在: %s", fp) or string.format("不存在: %s", fp))
end

-- ==================== UI ====================

local function build_ui()
    main_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = W, h = H, color = C_BG
    })

    -- title
    local th = 44
    local tb = airui.container({ parent = main_container, x = 0, y = 0, w = W, h = th, color = C_SUCCESS })
    airui.label({ parent = tb, x = 0, y = 6, w = W, h = 36, text = "文件系统测试", font_size = 20, color = C_WHITE, align = airui.TEXT_ALIGN_CENTER })
    airui.button({ parent = tb, x = 4, y = 6, w = 36, h = 32, text = "X", font_size = 17,
        style = { bg_color = C_SUCCESS, text_color = C_WHITE, radius = 6, border_width = 0 },
        on_click = function() exwin.close(window_id) end })

    -- info line
    local iy = th
    airui.container({ parent = main_container, x = 0, y = iy, w = W, h = 28, color = C_BG })
    airui.label({ parent = main_container, x = 8, y = iy + 2, w = W - 16, h = 24,
        text = "注意: 与fskv不同，受沙箱挂载点映射影响", font_size = 11, color = C_GRAY })

    -- content
    local cy = iy + 28
    local cont = airui.container({ parent = main_container, x = 0, y = cy, w = W, h = H - cy, color = C_BG })
    local kb = airui.keyboard({ mode = "text", auto_hide = true, preview = true, w = W, h = 150, bg_color = C_CARD })

    local y = 4
    local lw = 46

    airui.label({ parent = cont, x = 8, y = y, w = lw, h = 30, text = "存储:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    path_dropdown = airui.dropdown({
        parent = cont, x = 58, y = y, w = W - 66, h = 30,
        options = storage_labels, default_index = 0,
        style = { bg_color = C_CARD, border_color = C_DIV, radius = 6 },
        on_change = function(self, idx)
            current_storage = storage_paths[idx + 1] or "/ram/"
        end
    })
    y = y + 34

    airui.label({ parent = cont, x = 8, y = y, w = lw, h = 30, text = "名称:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    name_input = airui.textarea({ parent = cont, x = 58, y = y, w = W - 66, h = 30, placeholder = "文件或目录名", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 34

    airui.label({ parent = cont, x = 8, y = y, w = lw, h = 30, text = "内容:", font_size = 16, color = C_TEXT, align = airui.TEXT_ALIGN_RIGHT })
    content_input = airui.textarea({ parent = cont, x = 58, y = y, w = W - 66, h = 44, placeholder = "文件内容", font_size = 14, color = C_TEXT, keyboard = kb })
    y = y + 50

    local bh = 32
    local bw = 72
    airui.button({ parent = cont, x = 6, y = y, w = bw, h = bh, text = "写入", font_size = 14,
        style = { bg_color = C_PRIMARY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_write })
    airui.button({ parent = cont, x = 82, y = y, w = bw, h = bh, text = "读取", font_size = 14,
        style = { bg_color = C_SUCCESS, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_read })
    airui.button({ parent = cont, x = 158, y = y, w = bw, h = bh, text = "删除", font_size = 14,
        style = { bg_color = C_DANGER, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_delete })
    airui.button({ parent = cont, x = 234, y = y, w = bw, h = bh, text = "建目录", font_size = 14,
        style = { bg_color = C_ACCENT, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_mkdir })
    y = y + 38

    airui.button({ parent = cont, x = 6, y = y, w = bw, h = bh, text = "列目录", font_size = 14,
        style = { bg_color = C_GRAY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_list })
    airui.button({ parent = cont, x = 82, y = y, w = bw, h = bh, text = "大小", font_size = 14,
        style = { bg_color = C_GRAY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_file_size })
    airui.button({ parent = cont, x = 158, y = y, w = bw, h = bh, text = "存在?", font_size = 14,
        style = { bg_color = C_GRAY, text_color = C_WHITE, radius = 7, border_width = 0 }, on_click = do_exists })
    y = y + 38

    -- hint
    airui.label({ parent = cont, x = 8, y = y, w = W - 16, h = 50, text =
        "/ram/xxx -> /ram/app_store/fs_test/data/xxx\n"
        .. "/sd/xxx -> /sd/app_store/fs_test/data/xxx\n"
        .. "/xxx -> /app_store/fs_test/data/xxx",
        font_size = 10, color = C_GRAY })
    y = y + 54

    airui.container({ parent = cont, x = 8, y = y, w = W - 16, h = 1, color = C_DIV })
    y = y + 6

    result_label = airui.label({ parent = cont, x = 8, y = y, w = W - 16, h = H - cy - y - 8, text = "选择存储和文件名开始", font_size = 13, color = C_TEXT })
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

sys.subscribe("OPEN_FS_TEST_WIN", open_handler)
