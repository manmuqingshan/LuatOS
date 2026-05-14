
--[[
@module  medical_control_win
@summary  智能医疗设备中控系统 - 患者监护系统
@version 1.0
@date    2026-05-12
@author  马亚丹
]]

local win_id = nil
local main_container = nil

-- UI控件引用
local hr_label = nil
local spo2_label = nil
local bp_sys_label = nil
local bp_dia_label = nil
local temp_label = nil
local resp_label = nil
local hr_trend_label = nil
local spo2_trend_label = nil
local bp_trend_label = nil
local temp_trend_label = nil
local resp_trend_label = nil
local infusion_rate_label = nil
local oxygen_label = nil
local vent_mode_btn = nil
local vent_mode_label = nil
local emergency_stop_btn = nil
local humidifier_btn = nil
local humidifier_label = nil
local suction_btn = nil
local suction_label = nil
local mute_alarm_btn = nil
local mute_alarm_label = nil
local reset_alarm_btn = nil
local volume_label = nil
local alert_message_label = nil
local alert_panel = nil
local alert_badge = nil
local datetime_label = nil
local sys_status_label = nil
local led_indicator = nil
local toast_container = nil
local toast_timer = nil
local ecg_canvas = nil

-- 内部状态
local current_hr = 78
local current_spo2 = 96
local current_bp_sys = 118
local current_bp_dia = 76
local current_temp = 36.8
local current_resp = 16
local infusion_rate = 80
local oxygen_conc = 40
local vent_mode_active = false
local humidifier_state = true
local suction_state = false
local alarm_muted = false
local emergency_flag = false
local volume_level = 45
local ecg_phase = 0
local ecg_timer = nil
local dynamic_timer = nil
local datetime_timer = nil

-- 报警阈值配置
local ALERT_CONFIG = {
    hr_low = 50,
    hr_high = 120,
    spo2_low = 90,
    bp_sys_low = 90,
    bp_sys_high = 160,
    temp_normal_low = 36.5,
    temp_normal_high = 37.0,
    temp_high = 38.0,
    temp_low = 35.5,
    resp_low = 8,
    resp_high = 30
}

-- 获取颜色配置
local function get_color_config()
    return {
        normal = { text = 0x2E7D32, bg = 0xC8E6C9 },
        warning = { text = 0xED6C02, bg = 0xED6C0226 },
        critical = { text = 0xE57373, bg = 0xFFEBEE },
        white = 0xF0F9FF,
        dark_text = 0x1B5E20,
        primary = 0x4CAF50,
        warning_btn = 0xE65100,
        card_bg = 0xE8F5E9,
        header_bg = 0x2E7D32,
        container_bg = 0xF1F8F4,
        light_bg = 0xE0F2E1,
        medical_green = 0x4CAF50,
        medical_red = 0xE57373
    }
end

-- 显示临时提示
local function show_toast(msg, color)
    if toast_container then
        toast_container:destroy()
        toast_container = nil
    end
    
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    
    local colors = get_color_config()
    local border_color = color or 0x64B5F6
    local text_color = 0x1976D2
    local bg_color = 0xE3F2FD
    
    if color == colors.critical.text then
        bg_color = 0xE57373FF
        text_color = 0xFFFFFF
    elseif color == colors.warning.text or color == colors.warning_btn then
        bg_color = colors.warning_btn
        border_color = colors.warning_btn
        text_color = 0xFFFFFF
    end
    
    toast_container = airui.container({
        parent = main_container,
        x = 80,
        y = 100,
        w = 320,
        h = 45,
        color = bg_color,
        radius = 22,
        border_color = border_color,
        border_width = 2
    })
    
    airui.label({
        parent = toast_container,
        x = 15,
        y = 12,
        w = 290,
        h = 21,
        text = msg,
        font_size = 12,
        color = text_color,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    toast_timer = sys.timerStart(function()
        if toast_container then
            toast_container:destroy()
            toast_container = nil
        end
        toast_timer = nil
    end, 1800)
end

-- 评估当前报警状态
local function evaluate_alerts()
    local alerts = {}
    local alert_level = "normal"
    
    if emergency_flag then
        table.insert(alerts, "紧急停止激活")
        alert_level = "critical"
    end
    if current_hr < ALERT_CONFIG.hr_low then
        table.insert(alerts, "心动过缓")
        alert_level = "warning"
    end
    if current_hr > ALERT_CONFIG.hr_high then
        table.insert(alerts, "心动过速")
        alert_level = "warning"
    end
    if current_spo2 < ALERT_CONFIG.spo2_low then
        table.insert(alerts, "低血氧")
        alert_level = "warning"
    end
    if current_bp_sys < ALERT_CONFIG.bp_sys_low then
        table.insert(alerts, "低血压")
        alert_level = "warning"
    end
    if current_bp_sys > ALERT_CONFIG.bp_sys_high then
        table.insert(alerts, "高血压")
        alert_level = "warning"
    end
    if current_temp > ALERT_CONFIG.temp_high then
        table.insert(alerts, "高热")
        alert_level = "warning"
    elseif current_temp > ALERT_CONFIG.temp_normal_high then
        table.insert(alerts, "发热")
        alert_level = "warning"
    end
    if current_temp < ALERT_CONFIG.temp_low then
        table.insert(alerts, "低体温")
        alert_level = "warning"
    end
    if current_resp < ALERT_CONFIG.resp_low then
        table.insert(alerts, "呼吸过慢")
        alert_level = "warning"
    end
    if current_resp > ALERT_CONFIG.resp_high then
        table.insert(alerts, "呼吸急促")
        alert_level = "warning"
    end
    
    if emergency_flag then
        alert_level = "critical"
    end
    
    return {
        alerts = alerts,
        level = alert_level,
        has_alert = #alerts > 0
    }
end

-- 更新报警信息显示
local function update_alert_panel()
    if not exwin.is_active(win_id) then return end
    
    local alert_result = evaluate_alerts()
    local colors = get_color_config()
    local alert_msg = ""
    
    if #alert_result.alerts == 0 then
        alert_msg = "所有体征平稳"
    else
        alert_msg = table.concat(alert_result.alerts, " / ")
        if alarm_muted then
            alert_msg = alert_msg .. " (已静音)"
        end
    end
    
    if alert_message_label then
        alert_message_label:set_text(alert_msg)
        if alert_result.level == "critical" then
            alert_message_label:set_color(colors.critical.text)
        elseif alert_result.level == "warning" then
            alert_message_label:set_color(colors.warning.text)
        else
            alert_message_label:set_color(colors.dark_text)
        end
    end
    
    if alert_panel then
        if alert_result.level == "critical" then
            alert_panel:set_color(colors.critical.bg)
            alert_panel:set_border_color(colors.critical.text)
        elseif alert_result.level == "warning" then
            alert_panel:set_color(colors.warning.bg)
            alert_panel:set_border_color(colors.warning.text)
        else
            alert_panel:set_color(colors.normal.bg)
            alert_panel:set_border_color(colors.normal.text)
        end
    end
    
    -- 更新趋势标签
    if hr_trend_label then
        if current_hr < 60 then
            hr_trend_label:set_text("偏低")
            hr_trend_label:set_color(colors.warning.text)
        elseif current_hr > 100 then
            hr_trend_label:set_text("偏高")
            hr_trend_label:set_color(colors.warning.text)
        else
            hr_trend_label:set_text("正常")
            hr_trend_label:set_color(colors.normal.text)
        end
    end
    
    if spo2_trend_label then
        if current_spo2 < 92 then
            spo2_trend_label:set_text("需关注")
            spo2_trend_label:set_color(colors.warning.text)
        elseif current_spo2 >= 95 then
            spo2_trend_label:set_text("良好")
            spo2_trend_label:set_color(colors.normal.text)
        else
            spo2_trend_label:set_text("注意")
            spo2_trend_label:set_color(colors.warning.text)
        end
    end
    
    if bp_trend_label then
        if current_bp_sys < ALERT_CONFIG.bp_sys_low or current_bp_dia < 60 then
            bp_trend_label:set_text("偏低")
            bp_trend_label:set_color(colors.warning.text)
        elseif current_bp_sys > ALERT_CONFIG.bp_sys_high or current_bp_dia > 90 then
            bp_trend_label:set_text("偏高")
            bp_trend_label:set_color(colors.warning.text)
        else
            bp_trend_label:set_text("正常")
            bp_trend_label:set_color(colors.normal.text)
        end
    end
    
    if temp_trend_label then
        if current_temp < ALERT_CONFIG.temp_low then
            temp_trend_label:set_text("偏低")
            temp_trend_label:set_color(colors.warning.text)
        elseif current_temp < ALERT_CONFIG.temp_normal_low then
            temp_trend_label:set_text("偏低")
            temp_trend_label:set_color(colors.warning.text)
        elseif current_temp > ALERT_CONFIG.temp_high then
            temp_trend_label:set_text("高热")
            temp_trend_label:set_color(colors.warning.text)
        elseif current_temp > ALERT_CONFIG.temp_normal_high then
            temp_trend_label:set_text("偏高")
            temp_trend_label:set_color(colors.warning.text)
        else
            temp_trend_label:set_text("正常")
            temp_trend_label:set_color(colors.normal.text)
        end
    end
    
    if resp_trend_label then
        if current_resp < ALERT_CONFIG.resp_low then
            resp_trend_label:set_text("偏低")
            resp_trend_label:set_color(colors.warning.text)
        elseif current_resp > ALERT_CONFIG.resp_high then
            resp_trend_label:set_text("偏高")
            resp_trend_label:set_color(colors.warning.text)
        else
            resp_trend_label:set_text("正常")
            resp_trend_label:set_color(colors.normal.text)
        end
    end
    
    -- 更新LED状态
    if led_indicator then
        if alert_result.level == "critical" then
            led_indicator:set_color(colors.critical.text)
        elseif alert_result.level == "warning" then
            led_indicator:set_color(colors.warning.text)
        else
            led_indicator:set_color(colors.normal.text)
        end
    end
    
    if sys_status_label then
        if alert_result.level == "critical" then
            sys_status_label:set_text("系统警报")
        elseif alert_result.level == "warning" then
            sys_status_label:set_text("体征异常")
        else
            sys_status_label:set_text("系统在线")
        end
    end
end

-- 更新生命体征UI
local function update_vitals_ui()
    if not exwin.is_active(win_id) then return end
    
    if hr_label then
        hr_label:set_text(tostring(current_hr))
    end
    if spo2_label then
        spo2_label:set_text(tostring(math.floor(current_spo2)))
    end
    if bp_sys_label then
        bp_sys_label:set_text(tostring(current_bp_sys))
    end
    if bp_dia_label then
        bp_dia_label:set_text(tostring(current_bp_dia))
    end
    if temp_label then
        temp_label:set_text(string.format("%.1f", current_temp))
    end
    if resp_label then
        resp_label:set_text(tostring(current_resp))
    end
    
    update_alert_panel()
end

-- 更新输液泵UI
local function update_infusion_ui()
    if not exwin.is_active(win_id) then return end
    
    if infusion_rate_label then
        infusion_rate_label:set_text(infusion_rate .. " ml/h")
    end
end

-- 更新氧气UI
local function update_oxygen_ui()
    if not exwin.is_active(win_id) then return end
    
    if oxygen_label then
        oxygen_label:set_text(oxygen_conc .. " %")
    end
end

-- 更新音量UI
local function update_volume_ui()
    if not exwin.is_active(win_id) then return end
    
    if volume_label then
        volume_label:set_text("音量: " .. volume_level .. "%")
    end
end

-- 更新日期时间
local function update_datetime()
    if not exwin.is_active(win_id) then return end
    if not datetime_label then return end
    
    local t = os.date("*t")
    local datetime_str = string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
    datetime_label:set_text(datetime_str)
end

-- 紧急停止
local function set_emergency_stop(active)
    emergency_flag = active
    if active then
        infusion_rate = 0
        oxygen_conc = 21
        update_infusion_ui()
        update_oxygen_ui()
        show_toast("紧急停止已触发！", get_color_config().normal.text)
    end
    update_alert_panel()
end

-- 模拟动态数据更新
local function simulate_dynamic_data()
    if emergency_flag then return end
    
    -- 心率
    local hr_delta = (math.random() - 0.5) * 1.5
    current_hr = math.min(145, math.max(45, math.floor(current_hr + hr_delta)))
    
    -- 血氧
    local spo2_delta = (math.random() - 0.5) * 0.8
    current_spo2 = math.min(100, math.max(82, math.floor((current_spo2 + spo2_delta) * 10) / 10))
    
    -- 血压
    local bp_sys_delta = (math.random() - 0.5) * 3
    current_bp_sys = math.min(170, math.max(85, math.floor(current_bp_sys + bp_sys_delta)))
    local bp_dia_delta = (math.random() - 0.5) * 2
    current_bp_dia = math.min(100, math.max(55, math.floor(current_bp_dia + bp_dia_delta)))
    
    -- 体温
    local temp_delta = (math.random() - 0.5) * 0.1
    current_temp = math.min(39.2, math.max(35.0, math.floor((current_temp + temp_delta) * 10) / 10))
    
    -- 呼吸
    local resp_delta = (math.random() - 0.5) * 0.8
    current_resp = math.min(32, math.max(7, math.floor(current_resp + resp_delta)))
    
    update_vitals_ui()
end

-- 更新按钮状态
local function update_buttons_state()
    if not exwin.is_active(win_id) then return end
    
    local colors = get_color_config()
    
    -- 呼吸机模式按钮
    if vent_mode_btn and vent_mode_label then
        if vent_mode_active then
            vent_mode_btn:set_color(colors.medical_green)
            vent_mode_label:set_text("呼吸机: 控制")
        else
            vent_mode_btn:set_color(colors.light_bg)
            vent_mode_label:set_text("呼吸机: 辅助")
        end
    end
    
    -- 湿化器按钮
    if humidifier_btn and humidifier_label then
        if humidifier_state then
            humidifier_btn:set_color(colors.medical_green)
            humidifier_label:set_text("湿化器: 开")
        else
            humidifier_btn:set_color(colors.light_bg)
            humidifier_label:set_text("湿化器: 关")
        end
    end
    
    -- 吸引器按钮
    if suction_btn and suction_label then
        if suction_state then
            suction_btn:set_color(colors.medical_green)
            suction_label:set_text("吸引: 工作")
        else
            suction_btn:set_color(colors.light_bg)
            suction_label:set_text("吸引: 待机")
        end
    end
    
    -- 静音按钮
    if mute_alarm_btn and mute_alarm_label then
        if alarm_muted then
            mute_alarm_btn:set_color(colors.medical_green)
            mute_alarm_label:set_text("取消静音")
        else
            mute_alarm_btn:set_color(colors.light_bg)
            mute_alarm_label:set_text("暂时静音")
        end
    end
end

-- 重置为正常状态
local function reset_to_normal()
    local colors = get_color_config()
    
    current_hr = 78
    current_spo2 = 96
    current_bp_sys = 118
    current_bp_dia = 76
    current_temp = 36.8
    current_resp = 16
    infusion_rate = 80
    oxygen_conc = 40
    vent_mode_active = false
    humidifier_state = true
    suction_state = false
    alarm_muted = false
    emergency_flag = false
    volume_level = 45
    
    update_vitals_ui()
    update_infusion_ui()
    update_oxygen_ui()
    update_volume_ui()
    update_buttons_state()
    
    show_toast("已重置为正常监护状态", colors.primary)
end

-- 应用预设场景
local function apply_preset(preset_type)
    local colors = get_color_config()
    
    if preset_type == "normal" then
        current_hr = 75
        current_spo2 = 97
        current_bp_sys = 118
        current_bp_dia = 74
        current_temp = 36.6
        current_resp = 14
        infusion_rate = 70
        oxygen_conc = 40
        show_toast("已应用常规监护预设", colors.normal.text)
    elseif preset_type == "emergency" then
        current_hr = 112
        current_spo2 = 88
        current_bp_sys = 95
        current_bp_dia = 60
        current_temp = 37.9
        current_resp = 26
        infusion_rate = 120
        oxygen_conc = 60
        show_toast("已应用急救预设", colors.warning.text)
    elseif preset_type == "postop" then
        current_hr = 82
        current_spo2 = 94
        current_bp_sys = 125
        current_bp_dia = 78
        current_temp = 37.2
        current_resp = 18
        infusion_rate = 90
        oxygen_conc = 45
        show_toast("已应用术后恢复预设", colors.primary)
    end
    
    emergency_flag = false
    update_vitals_ui()
    update_infusion_ui()
    update_oxygen_ui()
    update_alert_panel()
end

-- 调整输液速率
local function adjust_infusion(delta)
    if emergency_flag then
        show_toast("紧急停止中，无法调节", get_color_config().warning.text)
        return
    end
    
    infusion_rate = infusion_rate + delta
    infusion_rate = math.max(0, math.min(200, infusion_rate))
    update_infusion_ui()
    show_toast("输液速率: " .. infusion_rate .. " ml/h")
end

-- 调整氧气浓度
local function adjust_oxygen(delta)
    if emergency_flag then
        show_toast("紧急停止中，无法调节", get_color_config().warning.text)
        return
    end
    
    oxygen_conc = oxygen_conc + delta
    oxygen_conc = math.max(21, math.min(100, oxygen_conc))
    update_oxygen_ui()
    show_toast("氧浓度: " .. oxygen_conc .. "%")
end

-- 调整音量
local function adjust_volume(delta)
    volume_level = volume_level + delta
    volume_level = math.max(0, math.min(100, volume_level))
    update_volume_ui()
end

-- 切换呼吸机模式
local function toggle_vent_mode()
    vent_mode_active = not vent_mode_active
    update_buttons_state()
    show_toast(vent_mode_active and "呼吸机切换到控制模式" or "呼吸机切换到辅助模式")
end

-- 切换紧急停止
local function toggle_emergency_stop()
    if not emergency_flag then
        set_emergency_stop(true)
    else
        set_emergency_stop(false)
        show_toast("紧急停止已解除", get_color_config().normal.text)
    end
    update_buttons_state()
end

-- 切换湿化器
local function toggle_humidifier()
    humidifier_state = not humidifier_state
    update_buttons_state()
end

-- 切换吸引器
local function toggle_suction()
    suction_state = not suction_state
    update_buttons_state()
end

-- 切换静音
local function toggle_mute()
    alarm_muted = not alarm_muted
    update_buttons_state()
    update_alert_panel()
end

-- 创建生命体征卡片
local function create_vitals_card(parent, x, y)
    local colors = get_color_config()
    
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = 450,
        h = 420,
        color = colors.card_bg,
        radius = 32,
        border_width = 1,
        border_color = 0xE0E0E0
    })
    
    -- 标题栏
    local header_container = airui.container({
        parent = card,
        x = 20,
        y = 15,
        w = 410,
        h = 40
    })
    
    airui.image({
        parent = header_container,
        x = 0,
        y = 12,
        w = 16,
        h = 16,
        src = "/luadb/heartbeat.png"
    })
    
    airui.label({
        parent = header_container,
        x = 22,
        y = 8,
        w = 120,
        h = 24,
        text = "生命体征",
        font_size = 18,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 实时监护徽章
    local badge_container = airui.container({
        parent = header_container,
        x = 300,
        y = 5,
        w = 110,
        h = 30,
        color = colors.light_bg,
        radius = 15
    })
    
    airui.label({
        parent = badge_container,
        x = 0,
        y = 8,
        w = 110,
        h = 14,
        text = "实时监护",
        font_size = 11,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 体征列表
    local vitals_list = airui.container({
        parent = card,
        x = 20,
        y = 65,
        w = 410,
        h = 340
    })
    
    -- 心率
    local hr_container = airui.container({
        parent = vitals_list,
        x = 0,
        y = 0,
        w = 410,
        h = 45
    })
    
    airui.image({
        parent = hr_container,
        x = 0,
        y = 16,
        w = 14,
        h = 14,
        src = "/luadb/heart.png"
    })
    
    airui.label({
        parent = hr_container,
        x = 20,
        y = 12,
        w = 80,
        h = 20,
        text = "心率",
        font_size = 14,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    hr_label = airui.label({
        parent = hr_container,
        x = 150,
        y = 5,
        w = 80,
        h = 35,
        text = "78",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = hr_container,
        x = 235,
        y = 16,
        w = 50,
        h = 14,
        text = "BPM",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    hr_trend_label = airui.label({
        parent = hr_container,
        x = 330,
        y = 12,
        w = 80,
        h = 20,
        text = "正常",
        font_size = 12,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 血氧
    local spo2_container = airui.container({
        parent = vitals_list,
        x = 0,
        y = 50,
        w = 410,
        h = 50
    })
    
    airui.image({
        parent = spo2_container,
        x = 0,
        y = 16,
        w = 14,
        h = 14,
        src = "/luadb/lungs.png"
    })
    
    airui.label({
        parent = spo2_container,
        x = 20,
        y = 12,
        w = 80,
        h = 20,
        text = "血氧",
        font_size = 14,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    spo2_label = airui.label({
        parent = spo2_container,
        x = 100,
        y = 8,
        w = 110,
        h = 30,
        text = "96",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = spo2_container,
        x = 215,
        y = 16,
        w = 40,
        h = 14,
        text = "%",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    spo2_trend_label = airui.label({
        parent = spo2_container,
        x = 330,
        y = 12,
        w = 80,
        h = 20,
        text = "良好",
        font_size = 12,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 血压
    local bp_container = airui.container({
        parent = vitals_list,
        x = 0,
        y = 100,
        w = 410,
        h = 45
    })
    
    airui.image({
        parent = bp_container,
        x = 0,
        y = 16,
        w = 14,
        h = 14,
        src = "/luadb/tachometer-alt.png"
    })
    
    airui.label({
        parent = bp_container,
        x = 20,
        y = 12,
        w = 80,
        h = 20,
        text = "血压",
        font_size = 14,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    bp_sys_label = airui.label({
        parent = bp_container,
        x = 150,
        y = 5,
        w = 50,
        h = 35,
        text = "118",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = bp_container,
        x = 205,
        y = 16,
        w = 20,
        h = 14,
        text = "/",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    bp_dia_label = airui.label({
        parent = bp_container,
        x = 230,
        y = 5,
        w = 50,
        h = 35,
        text = "76",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = bp_container,
        x = 285,
        y = 16,
        w = 50,
        h = 14,
        text = "mmHg",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    bp_trend_label = airui.label({
        parent = bp_container,
        x = 330,
        y = 12,
        w = 80,
        h = 20,
        text = "正常",
        font_size = 12,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 体温
    local temp_container = airui.container({
        parent = vitals_list,
        x = 0,
        y = 150,
        w = 410,
        h = 45
    })
    
    airui.image({
        parent = temp_container,
        x = 0,
        y = 16,
        w = 14,
        h = 14,
        src = "/luadb/temperature-low.png"
    })
    
    airui.label({
        parent = temp_container,
        x = 20,
        y = 12,
        w = 80,
        h = 20,
        text = "体温",
        font_size = 14,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    temp_label = airui.label({
        parent = temp_container,
        x = 150,
        y = 5,
        w = 80,
        h = 35,
        text = "36.8",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = temp_container,
        x = 235,
        y = 16,
        w = 40,
        h = 14,
        text = "°C",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    temp_trend_label = airui.label({
        parent = temp_container,
        x = 330,
        y = 12,
        w = 80,
        h = 20,
        text = "正常",
        font_size = 12,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 呼吸
    local resp_container = airui.container({
        parent = vitals_list,
        x = 0,
        y = 200,
        w = 410,
        h = 45
    })
    
    airui.image({
        parent = resp_container,
        x = 0,
        y = 16,
        w = 14,
        h = 14,
        src = "/luadb/wind.png"
    })
    
    airui.label({
        parent = resp_container,
        x = 20,
        y = 12,
        w = 80,
        h = 20,
        text = "呼吸",
        font_size = 14,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    resp_label = airui.label({
        parent = resp_container,
        x = 150,
        y = 5,
        w = 80,
        h = 35,
        text = "16",
        font_size = 28,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = resp_container,
        x = 235,
        y = 16,
        w = 50,
        h = 14,
        text = "bpm",
        font_size = 12,
        color = 0x81C784,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    resp_trend_label = airui.label({
        parent = resp_container,
        x = 330,
        y = 12,
        w = 80,
        h = 20,
        text = "正常",
        font_size = 12,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- ECG波形区域（简化版）
    local ecg_container = airui.container({
        parent = card,
        x = 20,
        y = 320,
        w = 410,
        h = 80,
        color = 0xC8E6C9,
        radius = 16
    })
    
    airui.image({
        parent = ecg_container,
        x = 15,
        y = 10,
        w = 12,
        h = 12,
        src = "/luadb/chart-line.png"
    })
    
    airui.label({
        parent = ecg_container,
        x = 32,
        y = 8,
        w = 100,
        h = 16,
        text = "ECG 趋势",
        font_size = 11,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    return card
end

-- 创建设备控制卡片
local function create_device_card(parent, x, y)
    local colors = get_color_config()
    
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = 450,
        h = 350,
        color = colors.card_bg,
        radius = 32,
        border_width = 1,
        border_color = 0xE0E0E0
    })
    
    -- 标题栏
    local header_container = airui.container({
        parent = card,
        x = 20,
        y = 15,
        w = 410,
        h = 40
    })
    
    airui.image({
        parent = header_container,
        x = 0,
        y = 12,
        w = 16,
        h = 16,
        src = "/luadb/sliders-h.png"
    })
    
    airui.label({
        parent = header_container,
        x = 22,
        y = 8,
        w = 120,
        h = 24,
        text = "设备控制",
        font_size = 18,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 联动可调徽章
    local badge_container = airui.container({
        parent = header_container,
        x = 300,
        y = 5,
        w = 110,
        h = 30,
        color = colors.light_bg,
        radius = 15
    })
    
    airui.label({
        parent = badge_container,
        x = 0,
        y = 8,
        w = 110,
        h = 14,
        text = "联动可调",
        font_size = 11,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 输液速率控制
    local infusion_container = airui.container({
        parent = card,
        x = 20,
        y = 65,
        w = 410,
        h = 70
    })
    
    local infusion_header = airui.container({
        parent = infusion_container,
        x = 0,
        y = 0,
        w = 410,
        h = 30
    })
    
    airui.image({
        parent = infusion_header,
        x = 0,
        y = 8,
        w = 14,
        h = 14,
        src = "/luadb/tint.png"
    })
    
    airui.label({
        parent = infusion_header,
        x = 20,
        y = 5,
        w = 100,
        h = 20,
        text = "输液泵速率",
        font_size = 14,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    infusion_rate_label = airui.label({
        parent = infusion_header,
        x = 250,
        y = 5,
        w = 160,
        h = 20,
        text = "80 ml/h",
        font_size = 14,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 输液调节按钮
    local infusion_btn_container = airui.container({
        parent = infusion_container,
        x = 0,
        y = 35,
        w = 410,
        h = 35
    })
    
    local infusion_minus_btn = airui.container({
        parent = infusion_btn_container,
        x = 0,
        y = 0,
        w = 100,
        h = 35,
        color = 0xA5D6A7,
        radius = 17,
        on_click = function() adjust_infusion(-5) end
    })
    
    airui.label({
        parent = infusion_minus_btn,
        x = 0,
        y = 8,
        w = 100,
        h = 18,
        text = "-5 ml/h",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local infusion_plus_btn = airui.container({
        parent = infusion_btn_container,
        x = 110,
        y = 0,
        w = 100,
        h = 35,
        color = 0xA5D6A7,
        radius = 17,
        on_click = function() adjust_infusion(5) end
    })
    
    airui.label({
        parent = infusion_plus_btn,
        x = 0,
        y = 8,
        w = 100,
        h = 18,
        text = "+5 ml/h",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 氧气浓度控制
    local oxygen_container = airui.container({
        parent = card,
        x = 20,
        y = 145,
        w = 410,
        h = 70
    })
    
    local oxygen_header = airui.container({
        parent = oxygen_container,
        x = 0,
        y = 0,
        w = 410,
        h = 30
    })
    
    airui.image({
        parent = oxygen_header,
        x = 0,
        y = 8,
        w = 14,
        h = 14,
        src = "/luadb/leaf.png"
    })
    
    airui.label({
        parent = oxygen_header,
        x = 20,
        y = 5,
        w = 120,
        h = 20,
        text = "供氧浓度",
        font_size = 14,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    oxygen_label = airui.label({
        parent = oxygen_header,
        x = 250,
        y = 5,
        w = 160,
        h = 20,
        text = "40 %",
        font_size = 14,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 氧气调节按钮
    local oxygen_btn_container = airui.container({
        parent = oxygen_container,
        x = 0,
        y = 35,
        w = 410,
        h = 35
    })
    
    local oxygen_minus_btn = airui.container({
        parent = oxygen_btn_container,
        x = 0,
        y = 0,
        w = 100,
        h = 35,
        color = 0xA5D6A7,
        radius = 17,
        on_click = function() adjust_oxygen(-1) end
    })
    
    airui.label({
        parent = oxygen_minus_btn,
        x = 0,
        y = 8,
        w = 100,
        h = 18,
        text = "-1 %",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local oxygen_plus_btn = airui.container({
        parent = oxygen_btn_container,
        x = 110,
        y = 0,
        w = 100,
        h = 35,
        color = 0xA5D6A7,
        radius = 17,
        on_click = function() adjust_oxygen(1) end
    })
    
    airui.label({
        parent = oxygen_plus_btn,
        x = 0,
        y = 8,
        w = 100,
        h = 18,
        text = "+1 %",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 设备控制按钮第一行
    local btn_row1 = airui.container({
        parent = card,
        x = 20,
        y = 225,
        w = 410,
        h = 50
    })
    
    -- 呼吸机模式按钮
    vent_mode_btn = airui.container({
        parent = btn_row1,
        x = 0,
        y = 5,
        w = 195,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        on_click = toggle_vent_mode
    })
    
    airui.image({
        parent = vent_mode_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/lungs.png"
    })
    
    vent_mode_label = airui.label({
        parent = vent_mode_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "呼吸机: 辅助",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 紧急停止按钮
    emergency_stop_btn = airui.container({
        parent = btn_row1,
        x = 215,
        y = 5,
        w = 195,
        h = 40,
        color = 0xFFEBEE,
        radius = 20,
        on_click = toggle_emergency_stop
    })
    
    airui.image({
        parent = emergency_stop_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/ban.png"
    })
    
    airui.label({
        parent = emergency_stop_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "紧急停止",
        font_size = 13,
        color = colors.medical_red,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 设备控制按钮第二行
    local btn_row2 = airui.container({
        parent = card,
        x = 20,
        y = 285,
        w = 410,
        h = 50
    })
    
    -- 湿化器按钮
    humidifier_btn = airui.container({
        parent = btn_row2,
        x = 0,
        y = 5,
        w = 195,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        on_click = toggle_humidifier
    })
    
    airui.image({
        parent = humidifier_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/water.png"
    })
    
    humidifier_label = airui.label({
        parent = humidifier_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "湿化器: 开",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 吸引器按钮
    suction_btn = airui.container({
        parent = btn_row2,
        x = 215,
        y = 5,
        w = 195,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        on_click = toggle_suction
    })
    
    airui.image({
        parent = suction_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/suction.png"
    })
    
    suction_label = airui.label({
        parent = suction_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "吸引: 待机",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    return card
end

-- 创建报警卡片
local function create_alert_card(parent, x, y)
    local colors = get_color_config()
    
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = 450,
        h = 300,
        color = colors.card_bg,
        radius = 32,
        border_width = 1,
        border_color = 0xE0E0E0
    })
    
    -- 标题栏
    local header_container = airui.container({
        parent = card,
        x = 20,
        y = 15,
        w = 410,
        h = 40
    })
    
    airui.image({
        parent = header_container,
        x = 0,
        y = 12,
        w = 16,
        h = 16,
        src = "/luadb/bell.png"
    })
    
    airui.label({
        parent = header_container,
        x = 22,
        y = 8,
        w = 120,
        h = 24,
        text = "临床警报",
        font_size = 18,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 状态徽章
    alert_badge = airui.container({
        parent = header_container,
        x = 300,
        y = 5,
        w = 110,
        h = 30,
        color = colors.light_bg,
        radius = 15
    })
    
    airui.label({
        parent = alert_badge,
        x = 0,
        y = 8,
        w = 110,
        h = 14,
        text = "主动监控",
        font_size = 11,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 报警面板
    alert_panel = airui.container({
        parent = card,
        x = 20,
        y = 65,
        w = 410,
        h = 80,
        color = colors.normal.bg,
        radius = 24,
        border_width = 4,
        border_color = colors.normal.text
    })
    
    local alert_header = airui.container({
        parent = alert_panel,
        x = 20,
        y = 15,
        w = 370,
        h = 25
    })
    
    airui.image({
        parent = alert_header,
        x = 0,
        y = 5,
        w = 14,
        h = 14,
        src = "/luadb/check-circle.png"
    })
    
    airui.label({
        parent = alert_header,
        x = 22,
        y = 2,
        w = 348,
        h = 20,
        text = "当前状态",
        font_size = 14,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    alert_message_label = airui.label({
        parent = alert_panel,
        x = 20,
        y = 40,
        w = 370,
        h = 30,
        text = "所有体征平稳，无异常报警",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 音量控制
    local volume_container = airui.container({
        parent = card,
        x = 20,
        y = 155,
        w = 410,
        h = 60
    })
    
    local volume_header = airui.container({
        parent = volume_container,
        x = 0,
        y = 0,
        w = 410,
        h = 25
    })
    
    airui.image({
        parent = volume_header,
        x = 0,
        y = 5,
        w = 14,
        h = 14,
        src = "/luadb/microphone-alt.png"
    })
    
    airui.label({
        parent = volume_header,
        x = 22,
        y = 2,
        w = 120,
        h = 20,
        text = "护士呼叫音量",
        font_size = 14,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 音量调节按钮
    local volume_btn_container = airui.container({
        parent = volume_container,
        x = 0,
        y = 30,
        w = 410,
        h = 30
    })
    
    local volume_minus_btn = airui.container({
        parent = volume_btn_container,
        x = 0,
        y = 0,
        w = 80,
        h = 30,
        color = 0xA5D6A7,
        radius = 15,
        on_click = function() adjust_volume(-5) end
    })
    
    airui.label({
        parent = volume_minus_btn,
        x = 0,
        y = 6,
        w = 80,
        h = 18,
        text = "-5",
        font_size = 12,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    volume_label = airui.label({
        parent = volume_btn_container,
        x = 90,
        y = 5,
        w = 150,
        h = 20,
        text = "音量: 45%",
        font_size = 13,
        color = colors.medical_green,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local volume_plus_btn = airui.container({
        parent = volume_btn_container,
        x = 250,
        y = 0,
        w = 80,
        h = 30,
        color = 0xA5D6A7,
        radius = 15,
        on_click = function() adjust_volume(5) end
    })
    
    airui.label({
        parent = volume_plus_btn,
        x = 0,
        y = 6,
        w = 80,
        h = 18,
        text = "+5",
        font_size = 12,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 报警控制按钮
    local alert_btn_container = airui.container({
        parent = card,
        x = 20,
        y = 225,
        w = 410,
        h = 50
    })
    
    -- 静音按钮
    mute_alarm_btn = airui.container({
        parent = alert_btn_container,
        x = 0,
        y = 5,
        w = 195,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        on_click = toggle_mute
    })
    
    airui.image({
        parent = mute_alarm_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/volume-mute.png"
    })
    
    mute_alarm_label = airui.label({
        parent = mute_alarm_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "暂时静音",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 重置报警按钮
    reset_alarm_btn = airui.container({
        parent = alert_btn_container,
        x = 215,
        y = 5,
        w = 195,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        on_click = reset_to_normal
    })
    
    airui.image({
        parent = reset_alarm_btn,
        x = 25,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/check-circle.png"
    })
    
    airui.label({
        parent = reset_alarm_btn,
        x = 45,
        y = 10,
        w = 145,
        h = 20,
        text = "重置警报",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    return card
end

-- 创建预设场景和底部操作栏
local function create_preset_bar(parent, x, y)
    local colors = get_color_config()
    
    local bar = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = 450,
        h = 90,
        color = colors.container_bg,
        border_width = 1,
        border_color = 0xE0E0E0
    })
    
    -- 预设按钮
    local preset_container = airui.container({
        parent = bar,
        x = 15,
        y = 15,
        w = 420,
        h = 40
    })
    
    -- 常规监护预设
    local normal_preset = airui.container({
        parent = preset_container,
        x = 0,
        y = 0,
        w = 130,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        border_width = 1,
        border_color = 0xC8E6C9,
        on_click = function() apply_preset("normal") end
    })
    
    airui.image({
        parent = normal_preset,
        x = 20,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/bed.png"
    })
    
    airui.label({
        parent = normal_preset,
        x = 40,
        y = 10,
        w = 85,
        h = 20,
        text = "常规监护",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 急救预设
    local emergency_preset = airui.container({
        parent = preset_container,
        x = 145,
        y = 0,
        w = 130,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        border_width = 1,
        border_color = 0xC8E6C9,
        on_click = function() apply_preset("emergency") end
    })
    
    airui.image({
        parent = emergency_preset,
        x = 15,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/ambulance.png"
    })
    
    airui.label({
        parent = emergency_preset,
        x = 35,
        y = 10,
        w = 90,
        h = 20,
        text = "急救预设",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 术后恢复预设
    local postop_preset = airui.container({
        parent = preset_container,
        x = 290,
        y = 0,
        w = 130,
        h = 40,
        color = colors.light_bg,
        radius = 20,
        border_width = 1,
        border_color = 0xC8E6C9,
        on_click = function() apply_preset("postop") end
    })
    
    airui.image({
        parent = postop_preset,
        x = 15,
        y = 13,
        w = 14,
        h = 14,
        src = "/luadb/procedures.png"
    })
    
    airui.label({
        parent = postop_preset,
        x = 35,
        y = 10,
        w = 90,
        h = 20,
        text = "术后恢复",
        font_size = 13,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 底部状态栏
    local status_container = airui.container({
        parent = bar,
        x = 15,
        y = 60,
        w = 420,
        h = 25
    })
    
    -- LED状态
    local led_container = airui.container({
        parent = status_container,
        x = 0,
        y = 5,
        w = 150,
        h = 15
    })
    
    led_indicator = airui.container({
        parent = led_container,
        x = 0,
        y = 1,
        w = 12,
        h = 12,
        color = colors.normal.text,
        radius = 6
    })
    
    sys_status_label = airui.label({
        parent = led_container,
        x = 18,
        y = 0,
        w = 130,
        h = 15,
        text = "系统在线",
        font_size = 11,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 右侧说明
    airui.image({
        parent = status_container,
        x = 300,
        y = 5,
        w = 12,
        h = 12,
        src = "/luadb/touch.png"
    })
    
    airui.label({
        parent = status_container,
        x = 318,
        y = 0,
        w = 100,
        h = 15,
        text = "触控交互",
        font_size = 11,
        color = colors.dark_text,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    return bar
end

-- 创建UI
local function create_ui()
    local colors = get_color_config()
    
    -- 主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = colors.container_bg,
        scrollable = false
    })
    
    -- 主背景
    local main_bg = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = colors.container_bg
    })
    
    -- 顶部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 60,
        color = colors.header_bg
    })
    
    -- 退出按钮
    airui.button({
        parent = status_bar,
        x = 10,
        y = 15,
        w = 60,
        h = 30,
        text = "退出",
        font_size = 12,
        text_color = 0xFFFFFF,
        bg_color = colors.medical_red,
        radius = 12,
        on_click = function()
            log.info("Medical_Control", "退出按钮被点击")
            if exwin and exwin.close and win_id then
                exwin.close(win_id)
            end
        end
    })
    
    -- 医院信息
    local hospital_container = airui.container({
        parent = status_bar,
        x = 80,
        y = 10,
        w = 230,
        h = 40
    })
    
    local hospital_name_container = airui.container({
        parent = hospital_container,
        x = 0,
        y = 0,
        w = 135,
        h = 28,
        color = 0x2E7D32,
        radius = 14
    })
    
    airui.image({
        parent = hospital_name_container,
        x = 12,
        y = 7,
        w = 14,
        h = 14,
        src = "/luadb/hospital-user.png"
    })
    
    airui.label({
        parent = hospital_name_container,
        x = 32,
        y = 4,
        w = 95,
        h = 20,
        text = "仁爱医疗 ICU",
        font_size = 10,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.image({
        parent = hospital_container,
        x = 145,
        y = 7,
        w = 14,
        h = 14,
        src = "/luadb/microchip.png"
    })
    
    airui.label({
        parent = hospital_container,
        x = 162,
        y = 4,
        w = 68,
        h = 20,
        text = "CareSync",
        font_size = 8,
        color = 0xFFFFFFCC,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 日期时间
    local datetime_container = airui.container({
        parent = status_bar,
        x = 320,
        y = 10,
        w = 150,
        h = 40,
        color = 0x1B5E20,
        radius = 20
    })
    
    datetime_label = airui.label({
        parent = datetime_container,
        x = 5,
        y = 10,
        w = 130,
        h = 20,
        text = "",
        font_size = 10,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 可滚动内容区域
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 480,
        h = 740,
        scrollable = true
    })
    
    -- 卡片区域（垂直排列）
    local cards_container = airui.container({
        parent = scroll_container,
        x = 15,
        y = 15,
        w = 450,
        h = 1190
    })
    
    -- 创建三个卡片
    create_vitals_card(cards_container, 0, 0)
    create_device_card(cards_container, 0, 440)
    create_alert_card(cards_container, 0, 810)
    create_preset_bar(cards_container, 0, 1120)
    
    -- 初始更新
    update_datetime()
    update_vitals_ui()
    update_infusion_ui()
    update_oxygen_ui()
    update_volume_ui()
    update_buttons_state()
end

-- 窗口生命周期管理
local function on_create()
    create_ui()
    
    -- 启动定时器
    datetime_timer = sys.timerLoopStart(update_datetime, 1000)
    dynamic_timer = sys.timerLoopStart(simulate_dynamic_data, 4000)
end

local function on_destroy()
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if datetime_timer then
        sys.timerStop(datetime_timer)
        datetime_timer = nil
    end
    if dynamic_timer then
        sys.timerStop(dynamic_timer)
        dynamic_timer = nil
    end
    if ecg_timer then
        sys.timerStop(ecg_timer)
        ecg_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus()
    update_vitals_ui()
    update_datetime()
end

local function on_lose_focus()
end

-- 打开窗口
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_MEDICAL_CONTROL_WIN", open_handler)

return {
    reset_to_normal = reset_to_normal,
    apply_preset = apply_preset
}