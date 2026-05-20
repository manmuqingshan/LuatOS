--[[
@module  tts_speaker
@summary 语音播报模块
@version 1.0
@date    2026.04.30
@usage
本模块负责语音播报功能，包括：
1. 开机播报
2. 电量播报
3. 时间播报
4. 消息播报
]]

local tts_speaker = {}
local exaudio = require "exaudio"
local exsip = require "exsip"

local TASK_NAME = "TTS_SPEAKER_TASK"

local is_playing = false
local tts_fallback_timer = nil
local voip_running = false
local current_priority = 0
local session_id = 0
local active_session = 0

local function cancel_tts_fallback_timer()
    if tts_fallback_timer then
        sys.timerStop(tts_fallback_timer)
        tts_fallback_timer = nil
    end
end

local function play_end(event, session)
    if event == exaudio.PLAY_DONE then
        if session ~= active_session then
            log.info("tts_speaker", "忽略过期回调，session=", session, "当前=", active_session)
            return
        end
        cancel_tts_fallback_timer()
        log.info("tts_speaker", "播放完成")
        is_playing = false
        current_priority = 0
        active_session = 0
        sys.publish("TTS_PLAY_DONE")
    end
end

local function format_digits(number)
    if not number then
        return nil
    end
    local digits = tostring(number):gsub("%D", "")
    if digits == "" then
        return nil
    end
    local spaced = digits:gsub("(%d)", "%1 ")
    return spaced:gsub("%s+$", "")
end

local function play_tts(text, priority)
    priority = priority or 0
    if voip_running then
        log.info("tts_speaker", "voip运行中，跳过TTS播报")
        return false
    end
    if is_playing then
        if priority > current_priority then
            log.info("tts_speaker", "高优先级打断当前播报", priority, ">", current_priority)
            -- 不主动调用 exaudio.play_stop，让 exaudio.play_start 内部处理打断
            -- 避免 SHUTDOWN/RESUME 频繁切换导致 TTS 引擎状态异常
        else
            log.info("tts_speaker", "正在播放中且优先级不够，忽略", priority, "<=", current_priority)
            return false
        end
    end

    session_id = session_id + 1
    local my_session = session_id
    active_session = my_session

    local audio_play_param = {
        type = 1,
        content = text,
        cbfnc = function(event)
            play_end(event, my_session)
        end,
        priority = priority
    }

    log.info("tts_speaker", "开始播报:", text)
    local ok, result = pcall(exaudio.play_start, audio_play_param)
    if ok and result then
        is_playing = true
        current_priority = priority
        cancel_tts_fallback_timer()
        tts_fallback_timer = sys.timerStart(function()
            log.warn("tts_speaker", "TTS回调超时，强制触发play_end")
            play_end(exaudio.PLAY_DONE, my_session)
        end, 8000)
    else
        if not ok then
            log.error("tts_speaker", "exaudio.play_start error:", result)
        else
            log.error("tts_speaker", "exaudio.play_start failed")
        end
        is_playing = false
        current_priority = 0
        active_session = 0
    end
    return ok and result
end

function tts_speaker.speak_boot()
    log.info("tts_speaker", "播报开机")
    play_tts("开机", 10)
end

function tts_speaker.speak_sip_ready_with_network(adapter)
    local text = "通话服务已就绪"
    if adapter then
        if adapter == 2 then
            local ok, rssi = pcall(function()
                local info = wlan.getInfo()
                return info and info.rssi
            end)
            if ok and type(rssi) == "number" then
                text = text .. "，当前已连接WiFi，信号强度" .. rssi .. "dBm"
                if rssi < -80 then
                    text = text .. "，信号较差"
                elseif rssi < -60 then
                    text = text .. "，信号一般"
                else
                    text = text .. "，信号良好"
                end
            else
                text = text .. "，当前已连接WiFi"
            end
        elseif adapter == 1 then
            local ok, csq = pcall(function()
                return mobile.csq()
            end)
            if ok and type(csq) == "number" then
                text = text .. "，当前已连接4G，信号强度为" .. csq
                if csq < 15 then
                    text = text .. "，信号较差"
                elseif csq < 25 then
                    text = text .. "，信号一般"
                else
                    text = text .. "，信号良好"
                end
            else
                text = text .. "，当前已连接4G"
            end
        else
            text = text .. "，当前已连接Ethernet"
        end
    end
    log.info("tts_speaker", "初始化播报:", text)
    play_tts(text, 5)
end

function tts_speaker.speak_incoming(number)
    local text
    local current_call = exsip.get_current_call()
    if current_call then
        local digits = format_digits(current_call)
        if digits then
            log.info("tts_speaker", "收到来电，号码", digits)
            text = string.format("收到来电，号码%s", digits)
        else
            log.info("tts_speaker", "收到来电，号码", number)
            text = string.format("收到来电，号码%s", number)
        end
    else
    -- if number then
    --     local current_call = exsip.get_current_call()
    --     if current_call then
    --         number = tostring(current_call.number)
    --         text = string.format("收到来电，号码%s", number)
    --     end
    -- else
        log.info("tts_speaker", "收到来电")
        text = "收到来电"
    end
    play_tts(text, 8)
end

function tts_speaker.speak_battery()
    log.info("tts_speaker", "播报电量")
    
    adc.open(adc.CH_VBAT)
    local vbat = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    
    log.info("tts_speaker", "VBAT电压:", vbat, "mV")
    
    local voltage = vbat / 1000
    local level = 0
    
    if voltage >= 3.75 then
        level = 100
    elseif voltage >= 3.65 then
        level = 80
    elseif voltage >= 3.55 then
        level = 60
    elseif voltage >= 3.45 then
        level = 40
    elseif voltage >= 3.35 then
        level = 20
    else
        level = 10
    end
    
    local text = string.format("电量%d%%", level)
    play_tts(text, 6)
end

function tts_speaker.speak_time()
    log.info("tts_speaker", "播报时间")
    
    local time = os.date("*t")
    local hour = time.hour
    local min = time.min
    
    local text = string.format("%d点%d分", hour, min)
    play_tts(text, 6)
end

function tts_speaker.speak_message()
    log.info("tts_speaker", "播报消息")
    play_tts("发送信息", 6)
end

function tts_speaker.speak_dialing(number)
    local digits = format_digits(number)
    local text
    if digits then
        log.info("tts_speaker", "播报拨号", digits)
        text = string.format("正在拨号，号码%s", digits)
    else
        log.info("tts_speaker", "播报拨号", number)
        text = string.format("正在拨号，号码%s", number)
    end
    play_tts(text, 8)
end

function tts_speaker.speak_hungup(reason)
    local reason_map = {
        peer_hangup = "对方挂断",
        local_hangup = "我方主动挂断",
        peer_cancel = "对方取消来电",
        call_failed = "呼叫失败",
        socket_closed = "网络断开",
        timeout = "呼叫超时",
        local_reject = "我方已拒接",
        -- Temporarily Unavailable = "对方暂时无法接听",
        -- Busy here = "对方正忙，请稍后再拨",
    }
    local text
    if reason and reason ~= "" then
        local mapped_reason = reason_map[reason]
        if mapped_reason then
            text = mapped_reason
        else
            text = "对方暂时无法接听,请稍后再拨"
        end
        log.info("tts_speaker", "播报挂断，原因", reason, "->", text)
    else
        log.info("tts_speaker", "播报挂断")
        text = "已挂断"
    end
    play_tts(text, 10)
end

function tts_speaker.speak(text, priority)
    play_tts(text, priority)
end

function tts_speaker.stop()
    if not is_playing then
        return
    end
    log.info("tts_speaker", "通话建立，停止当前播报")
    cancel_tts_fallback_timer()
    -- 不主动调用 exaudio.play_stop，避免 SHUTDOWN 破坏 voip 音频
    -- voip 启动后会自然抢占音频通道，TTS 被中断但不触发 audio.DONE
    is_playing = false
    current_priority = 0
    active_session = 0
    sys.publish("TTS_PLAY_DONE")
end

function tts_speaker.reset_audio()
    log.info("tts_speaker", "重置音频状态")
    local ok, err = pcall(function()
        exaudio.play_stop({type = 1})
    end)
    if not ok then
        log.error("tts_speaker", "重置音频失败:", err)
    end
end

function tts_speaker.set_voip_running(running)
    voip_running = running
end

-- 监听 playDone 事件，防止 TTS 完成后 SHUTDOWN 破坏 voip 音频
sys.subscribe("playDone", function()
    if voip_running then
        log.info("tts_speaker", "voip运行中，TTS完成事件触发，恢复音频")
        local ok, err = pcall(function()
            exaudio.pm(audio.RESUME)
        end)
        if not ok then
            log.error("tts_speaker", "恢复音频失败:", err)
        end
    end
end)

return tts_speaker