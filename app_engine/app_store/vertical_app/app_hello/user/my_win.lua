--[[
@module  my_win
@summary 基础入门应用窗口模块
@version 1.0.0
@date    2026.05.17
@author  马亚丹

运行核心逻辑：
1.订阅消息，运行打开窗口的处理函数：创建窗口、销毁窗口
2.创建窗口回调on_create()：create_ui()初始化UI 、启动定时器sys.timerLoopStart(update_tick, 1000)
3.create_ui()初始化UI：自适应分辨/自定义分辨率、添加图片和标题内容、添加关闭按钮
4.销毁窗口回调on_destroy()：sys.timerStop(update_timer_id)停止更新定时器、销毁主容器
5.定时器回调update_tick()：标题内容更新、添加当前时间显示
6.点击关闭按钮：触发销毁窗口消息，关闭应用

]]
-- my_win.lua - 主窗口模块
local win_id = nil                  --窗口ID
local main_container = nil          --主容器
local update_timer_id = nil         -- 定时器 ID
local title_label = nil             -- 标题标签
local current_time = nil            -- 当前时间
local width, height = lcd.getSize() --获取屏幕分辨率
local airui_size = nil              --airui屏幕自适应分辨率信息

-- 构建 UI
local function create_ui()
    -- 创建主容器作为最底层，所有子组件都加到主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        -- w = 720, h = 1280,       --根据屏幕分辨率自定义调整
        w = width,                  --自适应分辨率宽度
        h = height,                 --自适应分辨率高度
        color = 0x110f27
    })

    -- 获取屏幕自适应分辨率信息
    airui_size = airui.status()
    --判断当前是横屏还是竖屏，分别显示不同的图片
    if airui_size.w < airui_size.h then
        -- 图片背景（parent 指向 main_container）
        airui.image({
            parent = main_container,
            src = "/luadb/caoyuan.jpg",
            -- src = "/luadb/fengjing.jpg",
            x = 0,
            y = 0,
            w = width,
            h = height,
        })
    else
        -- 图片背景（parent 指向 main_container）
        airui.image({
            parent = main_container,
            src = "/luadb/fengjing.jpg",
            x = 0,
            y = 0,
            w = width,
            h = height,
        })
    end


    -- 标题文字（parent 指向 main_container）
    title_label = airui.label({
        parent = main_container,
        text = "Hello World!            一起来看大好河山",
        --x = 60,                       --根据屏幕分辨率自定义调整
        --y = 120,                      --根据屏幕分辨率自定义调整
        x = airui_size.w / 3,           --根据屏幕分辨率自适应
        y = airui_size.h / 6,           --根据屏幕分辨率自适应
        w = 300,                        
        h = 50,
        font_size = 24,
        color = 0xD81CEF
    })


    -- 关闭按钮（parent 指向 main_container）
    airui.button({
        parent = main_container,
        x = airui_size.w - 100,         --根据屏幕分辨率自适应
        y = airui_size.h - 50,          --根据屏幕分辨率自适应
        w = 100,
        h = 40,
        text = "关闭应用",
        font_size = 14,
        style = { bg_color = 0x2563EB, text_color = 0xFFFFFF, radius = 8, border_width = 0 },
        on_click = function()
            -- 关闭当前窗口
            exwin.close(win_id)         
        end
    })
end


-- 定时器回调函数，定时刷新 UI
local function update_tick()
    -- 定时器回调中的逻辑...
    current_time = os.date("%Y-%m-%d %H:%M:%S")
    if title_label then
        title_label:set_text("Hello World 当前时间  " .. current_time)
    end
    log.info("my_win", "当前时间: " .. current_time)
end

-- 窗口创建回调：初始化UI和定时器
local function on_create()
    create_ui()
    -- 启动定时器，每秒更新时间显示
    update_timer_id = sys.timerLoopStart(update_tick, 1000)
    log.info("my_win", "窗口创建")
end

-- 窗口销毁回调：先停止定时器，再销毁主容器
local function on_destroy()
    -- 1. 停止定时器（必须手动停止，destroy 不会自动停止）
    if update_timer_id then
        sys.timerStop(update_timer_id)
        update_timer_id = nil
    end
    -- 2. 销毁主容器（自动递归销毁内部所有子组件）
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    log.info("my_win", "窗口销毁")
end

-- 打开窗口的处理函数
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
end

sys.subscribe("OPEN_MY_WIN", open_handler)
