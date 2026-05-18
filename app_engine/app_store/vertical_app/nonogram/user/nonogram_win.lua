--[[
@module  nonogram_win
@summary 数织游戏 - 游戏页面窗口模块
@version 1.0
@date    2026.05.13
@usage
本模块为数织游戏的游戏页面，包含网格渲染、工具栏事件处理与游戏交互。
订阅"OPEN_NONOGRAM_WIN"事件打开窗口。
]]

local nonogram = require("nonogram")

-- ========================================
-- 模块级变量
-- ========================================

-- 窗口和容器引用
local win_id = nil
local main_container = nil
local content_container = nil

-- 网格
local grid_buttons = {}
local grid_container = nil

-- 行/列提示标签
local row_clue_labels = {}
local col_clue_labels = {}

-- 工具栏控件
local mode_btn = nil
local size_select = nil
local status_label = nil

-- 网格尺寸常量
local ROW_CLUE_W = 36
local COL_CLUE_H = 40
local GRID_AVAIL_W = 280

-- ========================================
-- 内部函数
-- ========================================

--[[
内部函数：返回主菜单
@local
@function go_back
]]
local function go_back()
    exwin.close(win_id)
end

--[[
内部函数：更新单个格子样式
@local
@function update_cell
@param r 行
@param c 列
]]
local function update_cell(r, c)
    local btn = grid_buttons[r][c]
    if not btn then return end
    local val = nonogram.state.cells[r][c]
    if val == 1 then
        btn:set_text("")
        btn:set_style({ bg_color = 0x1A1A2E, border_color = 0x888888, border_width = 1, bg_opa = 255 })
    elseif val == -1 then
        btn:set_text("x")
        btn:set_style({ bg_color = 0xFFFFFF, border_color = 0xCCCCCC, border_width = 1, text_color = 0xBBBBBB, bg_opa = 255 })
    else
        btn:set_text("")
        btn:set_style({ bg_color = 0xFFFFFF, border_color = 0xCCCCCC, border_width = 1, bg_opa = 255 })
    end
end

--[[
内部函数：更新行列提示完成状态
@local
@function update_clues
]]
local function update_clues()
    local size = nonogram.state.size
    local cells = nonogram.state.cells
    if size == 0 then return end

    -- 检查行
    for ri = 1, size do
        local filled = {}
        for ci = 1, size do
            filled[ci] = cells[ri][ci] == 1 and 1 or 0
        end
        local cl = nonogram.calcClues(filled)
        local orig = nonogram.state.rowClues[ri]
        local done = #cl == #orig
        if done then
            for k = 1, #cl do
                if cl[k] ~= orig[k] then done = false; break end
            end
        end
        if row_clue_labels[ri] then
            row_clue_labels[ri]:set_color(done and 0xAAAAAA or 0x666666)
        end
    end

    -- 检查列
    for ci = 1, size do
        local col = {}
        for ri = 1, size do
            col[ri] = cells[ri][ci] == 1 and 1 or 0
        end
        local cl = nonogram.calcClues(col)
        local orig = nonogram.state.colClues[ci]
        local done = #cl == #orig
        if done then
            for k = 1, #cl do
                if cl[k] ~= orig[k] then done = false; break end
            end
        end
        if col_clue_labels[ci] then
            col_clue_labels[ci]:set_color(done and 0xAAAAAA or 0x666666)
        end
    end
end

--[[
内部函数：重建整个网格
@local
@function rebuild_grid
]]
local function rebuild_grid()
    local size = nonogram.state.size
    if size == 0 then return end

    -- 销毁旧网格容器
    if grid_container then
        grid_container:destroy()
        grid_container = nil
    end

    grid_buttons = {}
    row_clue_labels = {}
    col_clue_labels = {}

    -- 计算格子大小
    local cs = math.floor(GRID_AVAIL_W / size) - 1

    -- 创建网格容器
    local gridH = COL_CLUE_H + size * (cs + 1) + 12
    grid_container = airui.container({
        parent = content_container,
        x = 0,
        y = 78,
        w = 320,
        h = gridH,
        color = 0xE8E9EB
    })

    -- 列提示
    for ci = 1, size do
        local clues = nonogram.state.colClues[ci]
        local text = ""
        for k, v in ipairs(clues) do
            if k > 1 then text = text .. "\n" end
            text = text .. v
        end
        local label = airui.label({
            parent = grid_container,
            x = ROW_CLUE_W + (ci - 1) * (cs + 1),
            y = 0,
            w = cs + 1,
            h = COL_CLUE_H,
            text = text,
            font_size = 10,
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
        col_clue_labels[ci] = label
    end

    -- 行提示
    for ri = 1, size do
        local clues = nonogram.state.rowClues[ri]
        local text = table.concat(clues, " ")
        local label = airui.label({
            parent = grid_container,
            x = 0,
            y = COL_CLUE_H + (ri - 1) * (cs + 1) + 2,
            w = ROW_CLUE_W,
            h = cs + 1,
            text = text,
            font_size = 10,
            color = 0x666666,
            align = airui.TEXT_ALIGN_RIGHT
        })
        row_clue_labels[ri] = label
    end

    -- 网格按钮
    for ri = 1, size do
        grid_buttons[ri] = {}
        for ci = 1, size do
            local x = ROW_CLUE_W + (ci - 1) * (cs + 1)
            local y = COL_CLUE_H + (ri - 1) * (cs + 1)
            local btn = airui.button({
                parent = grid_container,
                x = x,
                y = y,
                w = cs,
                h = cs,
                text = "",
                font_size = 12,
                style = {
                    bg_color = 0xFFFFFF,
                    border_color = 0xCCCCCC,
                    border_width = 1,
                    radius = 0
                },
                on_click = function()
                    nonogram.toggleCell(ri, ci)
                    update_cell(ri, ci)
                    update_clues()
                end
            })
            grid_buttons[ri][ci] = btn
        end
    end
end

--[[
内部函数：检查并显示结果
@local
@function do_check
]]
local function do_check()
    if nonogram.state.size == 0 then return end
    local errors = nonogram.check()
    if #errors == 0 then
        airui.msgbox({
            title = "结果",
            text = "恭喜！解答正确！",
            buttons = { "确定" },
            on_action = function(self, label)
                if label == "确定" then self:hide() end
            end
        })
    else
        -- 标红错误格子
        for _, e in ipairs(errors) do
            local btn = grid_buttons[e.r][e.c]
            if btn then
                btn:set_style({
                    border_color = 0xEA4335,
                    border_width = 2,
                    bg_color = e.expected == 1 and 0x4285F4 or nil,
                    bg_opa = e.expected == 1 and 50 or nil,
                })
            end
        end
        airui.msgbox({
            title = "结果",
            text = "有 " .. #errors .. " 格填错",
            buttons = { "确定" },
            on_action = function(self, label)
                if label == "确定" then
                    self:hide()
                end
            end
        })
    end
end

--[[
内部函数：切换填色/打叉模式
@local
@function toggle_mode
]]
local function toggle_mode()
    if nonogram.state.mode == "fill" then
        nonogram.state.mode = "cross"
        mode_btn:set_text("x 打叉")
        mode_btn:set_style({
            bg_color = 0x9E9E9E,
            border_color = 0x9E9E9E,
            text_color = 0xFFFFFF
        })
    else
        nonogram.state.mode = "fill"
        mode_btn:set_text("■ 填色")
        mode_btn:set_style({
            bg_color = 0x1A73E8,
            border_color = 0x1A73E8,
            text_color = 0xFFFFFF
        })
    end
end

--[[
内部函数：生成新谜题
@local
@function new_game
]]
local function new_game()
    local options = { 5, 8, 10 }
    local idx = size_select:get_selected()
    local size = options[idx + 1]
    local ok = nonogram.newPuzzle(size)
    if ok then
        rebuild_grid()
        log.info("nonogram", "新谜题已生成")
        status_label:set_text("新谜题已生成")
    else
        log.error("nonogram", "生成新谜题失败")
        status_label:set_text("生成失败，请重试")
    end
end

--[[
内部函数：显示游戏说明弹窗
@local
@function show_help
]]
local function show_help()
    airui.msgbox({
        title = "游戏说明",
        text = "【游戏目标】\n根据每行每列的数字提示，\n在网格中填涂格子，\n还原出隐藏的像素图案。\n\n" ..
               "【数字提示的含义】\n数字表示该行/列中连续\n涂色格子的长度。\n例如 3 2 表示：\n■■■□■■（3格+间隔+2格）\n\n" ..
               "【操作方式】\n【■ 填色】模式：\n  点击格子填色/取消填色\n【x 打叉】模式：\n  点击格子标记叉号\n\n" ..
               "【按钮功能】\n生成：随机生成新谜题\n检查：验证答案，有错标红\n重置：清空当前进度",
        buttons = { "知道了" },
        on_action = function(self, label)
            if label == "知道了" then
                self:hide()
            end
        end
    })
end

-- ========================================
-- UI 构建
-- ========================================

--[[
内部函数：创建标题栏
@local
@function create_title_bar
@param parent object 父容器
]]
local function create_title_bar(parent)
    local bar = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = 320,
        h = 40,
        color = 0x1A73E8
    })

    -- 返回按钮
    airui.button({
        parent = bar,
        x = 6,
        y = 6,
        w = 48,
        h = 28,
        text = "返回",
        font_size = 14,
        on_click = function()
            log.info("nonogram", "返回主菜单")
            go_back()
        end
    })

    -- 标题
    airui.label({
        parent = bar,
        x = 60,
        y = 13,
        w = 200,
        h = 24,
        text = "数织",
        font_size = 18,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 说明按钮
    airui.button({
        parent = bar,
        x = 266,
        y = 6,
        w = 48,
        h = 28,
        text = "说明",
        font_size = 14,
        on_click = function()
            show_help()
        end
    })
end

--[[
内部函数：创建工具栏
@local
@function create_toolbar
@param parent object 父容器
]]
local function create_toolbar(parent)
    -- 第1行：尺寸选择 + 生成 + 填色
    size_select = airui.dropdown({
        parent = parent,
        x = 45,
        y = 8,
        w = 80,
        h = 28,
        options = { "5x5", "8x8", "10x10" },
        default_index = 2,
    })

    airui.button({
        parent = parent,
        x = 135,
        y = 8,
        w = 60,
        h = 28,
        text = "生成",
        font_size = 13,
        style = {
            bg_color = 0x1A73E8,
            border_color = 0x1A73E8,
            text_color = 0xFFFFFF
        },
        on_click = function()
            new_game()
        end
    })

    mode_btn = airui.button({
        parent = parent,
        x = 205,
        y = 8,
        w = 60,
        h = 28,
        text = "■ 填色",
        font_size = 13,
        style = {
            bg_color = 0x1A73E8,
            border_color = 0x1A73E8,
            text_color = 0xFFFFFF
        },
        on_click = function()
            toggle_mode()
        end
    })

    -- 第2行：检查 + 重置
    airui.button({
        parent = parent,
        x = 75,
        y = 42,
        w = 70,
        h = 28,
        text = "检查",
        font_size = 13,
        on_click = function()
            do_check()
        end
    })

    airui.button({
        parent = parent,
        x = 175,
        y = 42,
        w = 70,
        h = 28,
        text = "重置",
        font_size = 13,
        on_click = function()
            nonogram.reset()
            for ri = 1, nonogram.state.size do
                for ci = 1, nonogram.state.size do
                    update_cell(ri, ci)
                end
            end
            update_clues()
            status_label:set_text("已重置")
        end
    })
end

--[[
内部函数：创建主界面
@local
@function create_ui
]]
local function create_ui()
    -- 主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xE8E9EB,
        parent = airui.screen
    })

    create_title_bar(main_container)

    -- 内容区域
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 40,
        w = 320,
        h = 440,
        color = 0xE8E9EB
    })

    create_toolbar(content_container)

    -- 状态栏
    status_label = airui.label({
        parent = content_container,
        x = 10,
        y = 415,
        w = 300,
        h = 20,
        text = "点击\"生成\"开始游戏",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- ========================================
-- exwin 窗口回调
-- ========================================

--[[
窗口创建回调
@local
@function on_create
]]
local function on_create()
    create_ui()
end

--[[
窗口销毁回调
@local
@function on_destroy
]]
local function on_destroy()
    log.info("nonogram_win", "关闭窗口")

    -- 清理网格引用
    grid_buttons = {}
    row_clue_labels = {}
    col_clue_labels = {}

    -- 销毁容器
    if grid_container then
        grid_container:destroy()
        grid_container = nil
    end
    if content_container then
        content_container:destroy()
        content_container = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

--[[
窗口获取焦点回调
@local
@function on_get_focus
]]
local function on_get_focus()
    log.info("nonogram_win", "get_focus")
end

--[[
窗口失去焦点回调
@local
@function on_lose_focus
]]
local function on_lose_focus()
    log.info("nonogram_win", "lose_focus")
end

-- ========================================
-- 窗口打开入口
-- ========================================

--[[
打开窗口的处理器
@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

-- ========================================
-- 事件订阅
-- ========================================

sys.subscribe("OPEN_NONOGRAM_WIN", open_handler)
