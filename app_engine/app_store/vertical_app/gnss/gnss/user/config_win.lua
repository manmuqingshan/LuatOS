--[[
@module  config_win
@summary 配置页面模块
@version 1.0
@date    2026.03.16
@author  李源龙
@usage
本模块为配置页面，用于设置GPS定位相关的参数。
订阅"OPEN_CONFIG_WIN"事件打开窗口。
]]
local config_win = {}
mcu.hardfault(0)
local win_id = nil
local main_container, content
local mode_radio, timer_start_input, gnss_duration_input, auto_close_switch
local shake_frequency_input, shake_window_input

-- 配置状态
config = {
    mode = 'always',
    timerStart = 120,
    gnssDuration = 40,
    gnssOnTime = 40,
    nextTriggerTime = 300,
    autoClose = false
}

-- 配置文件名
local CONFIG_FILE = "/config.json"

function config_win.get_config()
    return config
end
--[[
加载配置

@local
@function load_config
@return nil
@usage
-- 内部调用，从文件加载配置
]]
local function load_config()
    local file, err = io.open(CONFIG_FILE, "r")
    if file then
        local content = file:read("*a")
        file:close()
        
        local loaded_config = json.decode(content)
        if loaded_config then
            -- 合并加载的配置到默认配置
            for k, v in pairs(loaded_config) do
                config[k] = v
            end
            log.info("CONFIG", "配置加载成功")
        else
            log.warn("CONFIG", "配置文件解析失败")
        end
    else
        log.warn("CONFIG", "配置文件不存在，使用默认配置")
    end
end

--[[
保存配置

@local
@function save_config
@return nil
@usage
-- 内部调用，保存配置到文件
]]
local function save_config()
    local content = json.encode(config)
    local file, err = io.open(CONFIG_FILE, "w")
    if file then
        file:write(content)
        file:close()
        log.info("CONFIG", "配置保存成功")
    else
        log.error("CONFIG", "配置保存失败: " .. err)
    end
end

--[[
初始化配置UI

@local
@function init_config_ui
@return nil
@usage
-- 初始化配置页面的UI控件
]]
local function init_config_ui()
    -- 配置内容区域
    local config_content = airui.container({ parent = content, x=0, y=0, w=480, h=280, color=0x1e293b })
    
    -- 装饰性线条
    airui.container({ parent = config_content, x=10, y=10, w=460, h=1, color=0x38bdf8, radius = 0.5 })
    
    -- 工作模式选择
    local mode_section = airui.container({ parent = config_content, x=10, y=10, w=460, h=120, color=0x0f172a, radius = 8, scrollable = true })
    airui.label({ parent = mode_section, x=10, y=5, w=100, h=20, text="GNSS模式", font_size=12, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    
    -- 定时选项和震动选项的容器引用
    local timer_options = nil
    local shake_options = nil
    
    -- 定位成功后关闭选项的容器引用
    local auto_close_section = nil
    
    -- 先定义所有 radio 变量
    local timer_radio, always_radio, shake_radio
    
    -- 创建定时选项
    local function create_timer_options()
        if timer_options then return end
        timer_options = airui.container({ parent = config_content, x=10, y=140, w=460, h=80, color=0x0f172a, radius = 8 })
        airui.label({ parent = timer_options, x=10, y=5, w=100, h=20, text="定时设置", font_size=12, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        
        -- 创建数字虚拟键盘
        local numeric_keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 480,
            h = 200,
            mode = "numeric",
            auto_hide = true,
            preview = true
        })
        
        -- 定时时间
        airui.label({ parent = timer_options, x=10, y=35, w=60, h=30, text="定时时间", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        timer_start_input = airui.textarea({
            parent = timer_options,
            x=70,
            y=35,
            w=70,
            h=30,
            text=tostring(config.timerStart),
            font_size=10,
            color=0xe2e8f0,
            background_color=0x1e293b,
            border_color=0x475569,
            radius=4,
            align=airui.TEXT_ALIGN_CENTER,
            keyboard = numeric_keyboard
        })
        airui.label({ parent = timer_options, x=150, y=35, w=20, h=30, text="s", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        
        -- 打开时长
        airui.label({ parent = timer_options, x=180, y=35, w=60, h=30, text="打开时长", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        gnss_duration_input = airui.textarea({
            parent = timer_options,
            x=240,
            y=35,
            w=70,
            h=30,
            text=tostring(config.gnssDuration),
            font_size=10,
            color=0xe2e8f0,
            background_color=0x1e293b,
            border_color=0x475569,
            radius=4,
            align=airui.TEXT_ALIGN_CENTER,
            keyboard = numeric_keyboard
        })
        airui.label({ parent = timer_options, x=320, y=35, w=20, h=30, text="s", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    end
    
    -- 创建震动选项
    local function create_shake_options()
        if shake_options then return end
        shake_options = airui.container({ parent = config_content, x=10, y=140, w=460, h=80, color=0x0f172a, radius = 8 })
        airui.label({ parent = shake_options, x=10, y=5, w=100, h=20, text="震动设置", font_size=12, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        
        -- 创建数字虚拟键盘
        local numeric_keyboard = airui.keyboard({
            x = 0,
            y = -10,
            w = 480,
            h = 200,
            mode = "numeric",
            auto_hide = true,
            preview = true
        })
        
        -- GNSS开启时间
        airui.label({ parent = shake_options, x=10, y=35, w=60, h=30, text="开启时间", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        shake_frequency_input = airui.textarea({
            parent = shake_options,
            x=70,
            y=35,
            w=70,
            h=30,
            text=tostring(config.gnssOnTime),
            font_size=10,
            color=0xe2e8f0,
            background_color=0x1e293b,
            border_color=0x475569,
            radius=4,
            align=airui.TEXT_ALIGN_CENTER,
            keyboard = numeric_keyboard
        })
        airui.label({ parent = shake_options, x=150, y=35, w=20, h=30, text="s", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        
        -- 下次触发时间
        airui.label({ parent = shake_options, x=180, y=35, w=60, h=30, text="下次触发", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
        shake_window_input = airui.textarea({
            parent = shake_options,
            x=240,
            y=35,
            w=70,
            h=30,
            text=tostring(config.nextTriggerTime),
            font_size=10,
            color=0xe2e8f0,
            background_color=0x1e293b,
            border_color=0x475569,
            radius=4,
            align=airui.TEXT_ALIGN_CENTER,
            keyboard = numeric_keyboard
        })
        airui.label({ parent = shake_options, x=320, y=35, w=20, h=30, text="s", font_size=10, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    end
    
    -- 销毁定时选项
    local function destroy_timer_options()
        if timer_options then
            timer_options:destroy()
            timer_options = nil
            -- 子控件已销毁，须置 nil，避免对已释放对象调用 get_text/set_text
            timer_start_input = nil
            gnss_duration_input = nil
        end
    end
    
    -- 销毁震动选项
    local function destroy_shake_options()
        if shake_options then
            shake_options:destroy()
            shake_options = nil
            shake_frequency_input = nil
            shake_window_input = nil
        end
    end
    
    -- 创建定位成功后关闭选项
    local function create_auto_close_section()
        if auto_close_section then return end
        auto_close_section = airui.container({ parent = config_content, x=10, y=230, w=460, h=35, color=0x0f172a, radius = 8 })
        airui.label({ parent = auto_close_section, x=10, y=8, w=200, h=20, text="定位成功后关闭", font_size=11, color=0xe2e8f0, align = airui.TEXT_ALIGN_LEFT })
        auto_close_switch = airui.switch({
            parent = auto_close_section,
            x=400,
            y=8,
            w=60,
            h=20,
            checked = config.autoClose,
            on_change = function(self)
                config.autoClose = self:get_state()
            end
        })
    end
    
    -- 销毁定位成功后关闭选项
    local function destroy_auto_close_section()
        if auto_close_section then
            auto_close_section:destroy()
            auto_close_section = nil
            auto_close_switch = nil
        end
    end
    
    -- 定时开启模式
    timer_radio = airui.container({ parent = mode_section, x=10, y=25, w=440, h=25, color=(config.mode == 'timer' and 0x38bdf8 or 0x1e293b), radius = 5,
        on_click = function()
            config.mode = 'timer'
            -- 显示定时选项，隐藏震动选项
            destroy_shake_options()
            create_timer_options()
            -- 显示定位成功后关闭选项
            create_auto_close_section()
            -- 高亮选中项
            timer_radio:set_color(0x38bdf8)
            if always_radio then always_radio:set_color(0x1e293b) end
            if shake_radio then shake_radio:set_color(0x1e293b) end
        end
    })
    airui.label({ parent = timer_radio, x=30, y=3, w=400, h=20, text="定时开启", font_size=11, color=0xe2e8f0, align = airui.TEXT_ALIGN_LEFT })
    airui.container({ parent = timer_radio, x=10, y=5, w=14, h=14, color=0x38bdf8, radius = 7 })
    airui.container({ parent = timer_radio, x=13, y=8, w=8, h=8, color=0xfefefe, radius = 4 })
    
    -- 常开启模式
    always_radio = airui.container({ parent = mode_section, x=10, y=55, w=440, h=25, color=(config.mode == 'always' and 0x38bdf8 or 0x1e293b), radius = 5,
        on_click = function()
            config.mode = 'always'
            -- 隐藏定时和震动选项
            destroy_timer_options()
            destroy_shake_options()
            -- 隐藏定位成功后关闭选项
            destroy_auto_close_section()
            -- 高亮选中项
            if timer_radio then timer_radio:set_color(0x1e293b) end
            always_radio:set_color(0x38bdf8)
            if shake_radio then shake_radio:set_color(0x1e293b) end
        end
    })
    airui.label({ parent = always_radio, x=30, y=3, w=400, h=20, text="常开启", font_size=11, color=0xe2e8f0, align = airui.TEXT_ALIGN_LEFT })
    airui.container({ parent = always_radio, x=10, y=5, w=14, h=14, color=0x38bdf8, radius = 7 })
    airui.container({ parent = always_radio, x=13, y=8, w=8, h=8, color=0xfefefe, radius = 4 })
    
    -- 震动触发开启模式
    shake_radio = airui.container({ parent = mode_section, x=10, y=85, w=440, h=25, color=(config.mode == 'shake' and 0x38bdf8 or 0x1e293b), radius = 5,
        on_click = function()
            config.mode = 'shake'
            -- 显示震动选项，隐藏定时选项
            destroy_timer_options()
            create_shake_options()
            -- 显示定位成功后关闭选项
            create_auto_close_section()
            -- 高亮选中项
            if timer_radio then timer_radio:set_color(0x1e293b) end
            if always_radio then always_radio:set_color(0x1e293b) end
            shake_radio:set_color(0x38bdf8)
        end
    })
    airui.label({ parent = shake_radio, x=30, y=3, w=400, h=20, text="震动触发开启", font_size=11, color=0xe2e8f0, align = airui.TEXT_ALIGN_LEFT })
    airui.container({ parent = shake_radio, x=10, y=5, w=14, h=14, color=0x38bdf8, radius = 7 })
    airui.container({ parent = shake_radio, x=13, y=8, w=8, h=8, color=0xfefefe, radius = 4 })
    
    -- 初始化时根据当前模式显示或隐藏选项
    if config.mode == 'timer' then
        create_timer_options()
        create_auto_close_section()
    elseif config.mode == 'shake' then
        create_shake_options()
        create_auto_close_section()
    else
        -- 常开启模式
        destroy_timer_options()
        destroy_shake_options()
        destroy_auto_close_section()
    end
    
    -- 底部按钮
    local bottom_buttons = airui.container({ parent = config_content, x=10, y=270, w=460, h=35, color=0x0f172a, radius = 8 })
    
    -- 重置按钮
    local reset_btn = airui.container({ parent = bottom_buttons, x=10, y=5, w=215, h=30, color=0x64748b, radius = 5,
        on_click = function()
            -- 重置配置
            config = {
                mode = 'always',
                timerStart = 120,
                gnssDuration = 40,
                gnssOnTime = 40,
                nextTriggerTime = 300,
                autoClose = false
            }
            
            -- 重置UI
            timer_radio:set_color(0x1e293b)
            always_radio:set_color(0x38bdf8)
            shake_radio:set_color(0x1e293b)
            -- 销毁定时、震动和定位成功后关闭选项
            destroy_timer_options()
            destroy_shake_options()
            destroy_auto_close_section()
            -- -- 重新创建输入框并设置文本
            if timer_start_input then timer_start_input:set_text(config.timerStart) end
            if gnss_duration_input then gnss_duration_input:set_text(config.gnssDuration) end
            if shake_frequency_input then shake_frequency_input:set_text(config.gnssOnTime) end
            if shake_window_input then shake_window_input:set_text(config.nextTriggerTime) end
        end
    })
    airui.label({ parent = reset_btn, x=0, y=5, w=215, h=20, text="重置", font_size=12, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 保存按钮
    local save_btn = airui.container({ parent = bottom_buttons, x=235, y=5, w=215, h=30, color=0x38bdf8, radius = 5,
        on_click = function()
            -- 保存配置
            if timer_start_input then
                config.timerStart = tonumber(timer_start_input:get_text()) or 120
            end
            if gnss_duration_input then
                config.gnssDuration = tonumber(gnss_duration_input:get_text()) or 40
            end
            if shake_frequency_input then
                config.gnssOnTime = tonumber(shake_frequency_input:get_text()) or 5
            end
            if shake_window_input then
                config.nextTriggerTime = tonumber(shake_window_input:get_text()) or 10
            end
            -- 保存配置到文件
            save_config()
            -- 关闭配置页面
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({ parent = save_btn, x=0, y=5, w=215, h=20, text="保存", font_size=12, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建配置页面的UI
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0x0f172a })
    
    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x1e293b })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = header, x = 10, y = 5, w = 70, h = 30, color=0x38bdf8, radius = 5,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({ parent = back_btn, x=10, y=10, w=50, h=20, text="返回", font_size=14, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 标题
    airui.label({ parent = header, x=90, y=4, w=300, h=32, text="配置", font_size=24, color=0x38bdf8, align = airui.TEXT_ALIGN_CENTER })
    
    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0x1e293b })
    
    -- 加载配置
    load_config()
    
    -- 初始化配置UI
    init_config_ui()
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI
]]
local function on_create()
    create_ui()
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
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 获得焦点时的处理
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 失去焦点时的处理
end

-- 订阅打开配置页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CONFIG_WIN", open_handler)

load_config() -- 加载配置

return config_win