--[[
@module  wifi_app
@summary WiFi应用模块（Air1601/Air1602 业务逻辑层，事件驱动）
@version 1.2
@date    2026.05.19
@author  江访
@usage
== 状态机（从初始化到联网的完整链路 ==
 HW Init → WIFI_HW_READY
   → 自动扫描 → WIFI_SCAN_DONE
     → 连接热点 → wlan.connect()
       → WLAN_STA_INC CONNECTED  (L2 关联成功)
         → DHCP → IP_READY       (L3 IP 分配成功)
           → NTP sync → NTP_UPDATE (Internet 连通确认)
             → connectivity_verified = true

== 接收的事件（来自UI层）：==
  WIFI_ENABLE_REQ: {enabled}
  WIFI_SCAN_REQ
  WIFI_CONNECT_REQ: {ssid, password, advanced_config}
  WIFI_DISCONNECT_REQ
  WIFI_GET_STATUS_REQ
  WIFI_GET_CONFIG_REQ
  WIFI_GET_SAVED_LIST_REQ

== 发布的事件（给UI层）：==
  WIFI_SCAN_STARTED, WIFI_SCAN_DONE, WIFI_SCAN_TIMEOUT
  WIFI_CONNECTING, WIFI_CONNECTED, WIFI_DISCONNECTED
  WIFI_STATUS_UPDATED: {connected, ready, connectivity_verified, ...}
  WIFI_CONFIG_RSP: {config}
  WIFI_SAVED_LIST_RSP: {list}
  STATUS_WIFI_SIGNAL_UPDATED: level (0-4)

== 与storage层交互的事件：==
  WIFI_STORAGE_INIT_REQ / WIFI_STORAGE_INIT_RSP
  WIFI_STORAGE_LOAD_REQ / WIFI_STORAGE_LOAD_RSP
  WIFI_STORAGE_SAVE_REQ
  WIFI_STORAGE_SET_ENABLED_REQ / WIFI_STORAGE_SET_ENABLED_RSP
]]

require "wifi_storage"
local wifi_common = require "wifi_app_common"

-- 扫描超时时间（毫秒）
local SCAN_TIMEOUT = 20000
-- 网络信息更新间隔（毫秒），仅用于刷新IP/RSSI/BSSID等
local UPDATE_INTERVAL = 5000
-- 联网连通性确认超时（毫秒），IP_READY后等待NTP同步的最长时间
local CONNECTIVITY_TIMEOUT = 30000

-- WiFi当前状态
local wifi_state = {
    connected = false,           -- L2: 是否与AP关联成功
    ready = false,               -- L3: 是否获取到IP
    connectivity_verified = false,-- Internet: NTP同步是否成功（真正可联网）
    current_ssid = "",
    rssi = "--",
    ip = "--",
    netmask = "--",
    gateway = "--",
    bssid = "--",
    scan_results = {}
}

-- 保存的WiFi配置（从storage加载）
local saved_config = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
}

local scan_timer = nil           -- 扫描超时定时器
local update_timer = nil         -- 网络信息刷新定时器
local last_connect = nil         -- 上次连接状态（"CONNECTED"/"DISCONNECTED"）
local user_disconnect = false    -- 用户主动断开标记
local user_connect = false       -- 用户主动连接标记

local wifi_ready = false         -- airlink+wlan硬件是否就绪
local wifi_busy = false          -- 硬件初始化是否正在执行
local scan_busy = false          -- 扫描是否正在进行

--[[
更新WiFi状态并发布WIFI_STATUS_UPDATED事件
@param table status - 要更新的状态字段
]]
local function update_status(status)
    if not status then
        log.error("wifi_app", "更新WiFi状态时，状态对象为空")
        return
    end
    for k, v in pairs(status) do
        wifi_state[k] = v
    end
    wifi_common.update_status(wifi_state, saved_config)
end

--[[
刷新网络信息（IP/RSSI/BSSI/网关），并更新信号图标
]]
local function refresh_net_info()
    local function update_wifi_signal()
        local info = wlan.getInfo()
        if info and info.rssi then
            local rssi_val = info.rssi
            local signal_level = 0
            if rssi_val > -60 then signal_level = 4
            elseif rssi_val > -70 then signal_level = 3
            elseif rssi_val > -80 then signal_level = 2
            else signal_level = 1 end
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", signal_level)
        end
    end
    wifi_common.refresh_network_info(wifi_state, update_wifi_signal)
end

--[[
初始化airlink+wlan硬件
发布WIFI_HW_READY事件（成功或失败）
]]
local function init_wifi_hw()
    if wifi_ready then return end
    log.info("wifi_app", "初始化airlink+wlan硬件")
    gpio.setup(55, 0)
    gpio.set(55, 0)
    sys.wait(50)
    gpio.set(55, 1)
    sys.wait(120)
    airlink.config(airlink.CONF_SPI_ID, 1)
    airlink.config(airlink.CONF_SPI_CS, 8)
    airlink.config(airlink.CONF_SPI_RDY, 14)
    airlink.config(airlink.CONF_SPI_SPEED, 20 * 1000000)
    airlink.init()
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    airlink.start(airlink.MODE_SPI_MASTER)
    sys.wait(1000)
    local airlink_timeout = 0
    while not airlink.ready() do
        log.info("wifi_app", "等待airlink就绪...")
        sys.wait(100)
        airlink_timeout = airlink_timeout + 100
        if airlink_timeout >= 30000 then
            log.error("wifi_app", "airlink初始化超时，放弃本次初始化")
            wifi_busy = false
            wifi_ready = false
            sys.publish("WIFI_HW_READY", false)
            return
        end
    end
    log.info("wifi_app", "airlink就绪")
    wlan.init()
    wlan.setMode(wlan.STATIONAP)
    wifi_ready = true
    wifi_busy = false
    sys.wait(5000)
    log.info("wifi_app", "airlink+wlan硬件初始化完成")
    sys.publish("WIFI_HW_READY", true)
end

--[[
确保WiFi硬件已就绪，如未就绪则启动初始化任务
@return boolean - 是否已就绪
]]
local function ensure_wifi_ready()
    if wifi_ready then return true end
    if not wifi_busy then
        wifi_busy = true
        sys.taskInit(init_wifi_hw)
    end
    return false
end

--[[
处理WLAN_STA_INC事件（WiFi STA连接状态变化）
@param string event - "CONNECTED" 或 "DISCONNECTED"
@param string|number data - CONNECTED时是SSID，DISCONNECTED时是原因码
]]
local function handle_sta_event(event, data)
    log.info("wifi_app", "WiFi STA事件:", event, data)

    if event == "CONNECTED" then
        wifi_state.connected = true
        wifi_state.ready = false
        wifi_state.current_ssid = data
        wifi_state.connectivity_verified = false  -- 新连接，重置连通性确认

        sys.publish("WIFI_CONNECTED", data)
        -- L2关联成功但IP未就绪，不显示已连接图标（待IP_READY后更新）
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        last_connect = "CONNECTED"
        user_connect = false

        -- 启动定时刷新网络信息
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        update_timer = sys.timerLoopStart(refresh_net_info, UPDATE_INTERVAL)

    elseif event == "DISCONNECTED" then
        -- user_connect 为 true 说明是 on_connect_request 的连接失败（wlan.connect 未产生 CONNECTED）
        if user_connect then
            log.info("wifi_app", "用户发起的连接失败，重置状态以允许再次弹窗")
            last_connect = nil
        elseif last_connect == "DISCONNECTED" then
            -- 已断开状态，跳过重复事件（防抖）
            log.info("wifi_app", "已断开状态，跳过重复事件")
            return
        end

        -- disconnect_reason == "config" 说明是 on_connect_request 中先 wlan.disconnect() 产生的
        if disconnect_reason == "config" then
            log.info("wifi_app", "配置前断开，跳过事件处理")
            disconnect_reason = nil
            return
        end

        -- 重置所有WiFi状态
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.rssi = "--"
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        wifi_state.connectivity_verified = false

        -- 停止定时刷新
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end

        -- 发布断开事件（含原因）
        local reason_name = wifi_common.resolve_disconnect_reason(data)
        sys.publish("WIFI_DISCONNECTED", reason_name, data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        last_connect = "DISCONNECTED"
        user_connect = false

        -- 用户主动断开后自动扫描刷新列表
        if user_disconnect then
            log.info("wifi_app", "用户主动断开，只进行扫描")
            user_disconnect = false
            sys.publish("WIFI_SCAN_REQ")
        end
    end
end

--[[
处理IP就绪事件
发布WIFI_STATUS_UPDATED，设置DNS，启动联网连通性确认
@param string ip - IP地址
@param number adapter - 网卡适配器
]]
local function handle_ip_ready(ip, adapter)
    if adapter == socket.LWIP_STA then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("wifi_app", "WiFi IP就绪，DNS已设置:", ip)
        wifi_common.handle_ip_ready(ip, adapter, wifi_state, refresh_net_info)
        -- IP就绪但尚未确认联网，显示"已连无网"图标（待RSSI轮询覆盖）
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 5)

        -- IP就绪后，启动联网连通性确认（等待NTP同步）
        sys.taskInit(function()
            wifi_common.start_connectivity_verification(wifi_state, CONNECTIVITY_TIMEOUT)
        end)
    end
end

--[[
处理IP丢失事件
]]
local function handle_ip_lose(adapter)
    wifi_common.handle_ip_lose(adapter, wifi_state)
    wifi_state.connectivity_verified = false
end

--[[
处理WLAN_SCAN_DONE事件
]]
local function handle_scan_done()
    local scan_ref = {}
    scan_ref[1] = scan_timer
    wifi_common.handle_scan_done(wifi_state, scan_ref, function() scan_busy = false end)
    scan_timer = scan_ref[1]
end

--[[
处理扫描超时事件
]]
local function handle_scan_timeout()
    scan_timer = nil
    scan_busy = false
    wifi_common.handle_scan_timeout({})
end

--[[
自动扫描并查找最佳已保存网络
]]
local function auto_scan_verify()
    return wifi_common.auto_scan_and_verify(saved_config, SCAN_TIMEOUT + 5000)
end

--[[
运行开机自动连接（选择信号最强的已保存网络连接）
]]
local function run_auto_connect()
    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi开关已关闭，跳过自动连接")
        return
    end
    ensure_wifi_ready()
    if not wifi_ready then
        local ok = sys.waitUntil("WIFI_HW_READY", 15000)
        if not ok then
            log.error("wifi_app", "airlink+wlan硬件初始化超时")
            return
        end
    end
    log.info("wifi_app", "开始执行开机自动连接（选择信号最强的已保存网络）")
    if wifi_state.connected then
        log.info("wifi_app", "已连接WiFi，只进行扫描刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end
    local verify_result = auto_scan_verify()
    if verify_result.verified then
        log.info("wifi_app", "自动连接到最佳网络:", verify_result.ssid, "信号:", verify_result.signal)
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = verify_result.ssid,
            password = verify_result.password,
            advanced_config = verify_result.config and {
                need_ping = verify_result.config.need_ping,
                local_network_mode = verify_result.config.local_network_mode,
                ping_ip = verify_result.config.ping_ip,
                ping_time = verify_result.config.ping_time,
                auto_socket_switch = verify_result.config.auto_socket_switch
            }
        })
    else
        log.info("wifi_app", "附近没有已保存网络，等待用户手动连接")
    end
end

--[[
处理WIFI_STORAGE_LOAD_RSP事件
]]
local function on_storage_loaded(data)
    saved_config = data.config
    log.info("wifi_app", "加载配置完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)
    sys.taskInit(run_auto_connect)
end

--[[
处理WIFI_STORAGE_SET_ENABLED_RSP事件
]]
local function on_set_enabled(data)
    wifi_common.on_storage_set_enabled_rsp(data, saved_config)
end

--[[
处理WIFI_ENABLE_REQ事件（WiFi开关切换）
]]
local function on_enable_request(data)
    local enabled = data.enabled
    log.info("wifi_app", "收到开关请求:", enabled)

    if saved_config then
        saved_config.wifi_enabled = enabled
    end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", {enabled = enabled})

    if not enabled then
        log.info("wifi_app", "正在关闭WiFi网卡")
        if wifi_ready then
            wlan.disconnect()
        end
        -- 重置所有状态
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.rssi = "--"
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        wifi_state.scan_results = {}
        wifi_state.connectivity_verified = false
        update_status(wifi_state)
    else
        log.info("wifi_app", "正在开启WiFi网卡")
        sys.taskInit(function()
            ensure_wifi_ready()
            if not wifi_ready then
                sys.waitUntil("WIFI_HW_READY", 15000)
            end
            if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
                if wifi_state.connected then
                    log.info("wifi_app", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                    run_auto_connect()
                end
            end
        end)
    end
end

--[[
处理WIFI_SCAN_REQ事件（开始扫描WiFi热点）
]]
local function on_scan_request()
    log.info("wifi_app", "收到扫描请求")

    if not wifi_ready then
        ensure_wifi_ready()
        log.info("wifi_app", "等待WiFi硬件初始化完成后再扫描")
        sys.taskInit(function()
            sys.waitUntil("WIFI_HW_READY", 35000)
            if wifi_ready and not scan_busy then
                scan_busy = true
                wlan.scan()
                if scan_timer then sys.timerStop(scan_timer) end
                scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
                sys.publish("WIFI_SCAN_STARTED")
            end
        end)
        return
    end

    if scan_busy then
        log.info("wifi_app", "扫描已在进行中，跳过重复请求")
        return
    end

    scan_busy = true
    wlan.scan()
    if scan_timer then
        sys.timerStop(scan_timer)
    end
    scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
    sys.publish("WIFI_SCAN_STARTED")
end

--[[
处理WIFI_CONNECT_REQ事件（连接WiFi热点）
]]
local function on_connect_request(data)
    local ssid = data.ssid
    local password = data.password
    local adv_config = data.advanced_config

    log.info("wifi_app", "收到连接请求:", ssid)
    user_connect = true

    if not ssid or ssid == "" then
        sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
        return
    end
    if not password or password == "" then
        sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
        return
    end
    if saved_config and not saved_config.wifi_enabled then
        log.warn("wifi_app", "WiFi已关闭，无法连接")
        return
    end

    -- 保存凭证
    sys.publish("WIFI_STORAGE_SAVE_REQ", { ssid = ssid, password = password, advanced_config = adv_config })
    sys.publish("WIFI_CONNECTING", ssid)

    sys.taskInit(function()
        if not wifi_ready then
            ensure_wifi_ready()
            if not wifi_ready then
                local success = sys.waitUntil("WIFI_HW_READY", 15000)
                if not success then
                    log.error("wifi_app", "WiFi硬件初始化超时，无法连接")
                    sys.publish("WIFI_DISCONNECTED", "硬件初始化超时", -6)
                    return
                end
            end
        end
        -- 断开当前连接（如果有），使用"config"标记让handle_sta_event跳过这次DISCONNECTED
        disconnect_reason = "config"
        wlan.disconnect()
        sys.wait(500)
        local res = wlan.connect(ssid, password)
        if res then
            log.info("wifi_app", "WiFi连接已发起:", ssid)
        else
            log.error("wifi_app", "WiFi连接发起失败")
            sys.publish("WIFI_DISCONNECTED", "连接发起失败", -5)
        end
    end)
end

--[[
处理WIFI_DISCONNECT_REQ事件（用户主动断开连接）
]]
local function on_disconnect_request()
    log.info("wifi_app", "收到断开请求")
    user_disconnect = true
    wlan.disconnect()
    -- 注意：此处不清除 disconnect_reason。
    -- WLAN_STA_INC DISCONNECTED 事件会异步到来，
    -- handle_sta_event 通过 user_disconnect 标记判断是用户主动断开。
end

--[[
处理WIFI_GET_STATUS_REQ事件
]]
local function on_get_status()
    wifi_common.on_get_status_req(wifi_state, saved_config)
end

--[[
处理WIFI_GET_CONFIG_REQ事件
]]
local function on_get_config()
    wifi_common.on_get_config_req(saved_config)
end

--[[
处理WIFI_GET_SAVED_LIST_REQ事件
]]
local function on_get_saved_list()
    wifi_common.on_get_saved_list_req(saved_config)
end

--[[
处理WIFI_STORAGE_GET_SAVED_LIST_RSP事件
]]
local function on_saved_list_rsp(data)
    wifi_common.on_storage_get_saved_list_rsp(data)
end

--[[
处理WIFI_STORAGE_INIT_RSP事件
]]
local function on_storage_ready(data)
    wifi_common.on_storage_init_rsp(data)
end

--[[
初始化模块
]]
local function init_module()
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_ready)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

-- 订阅系统事件（放在文件末尾，确保所有函数已定义）
sys.subscribe("WLAN_STA_INC", handle_sta_event)
sys.subscribe("WLAN_SCAN_DONE", handle_scan_done)
sys.subscribe("IP_READY", handle_ip_ready)
sys.subscribe("IP_LOSE", handle_ip_lose)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", on_storage_loaded)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", on_set_enabled)
sys.subscribe("WIFI_ENABLE_REQ", on_enable_request)
sys.subscribe("WIFI_SCAN_REQ", on_scan_request)
sys.subscribe("WIFI_CONNECT_REQ", on_connect_request)
sys.subscribe("WIFI_DISCONNECT_REQ", on_disconnect_request)
sys.subscribe("WIFI_GET_STATUS_REQ", on_get_status)
sys.subscribe("WIFI_GET_CONFIG_REQ", on_get_config)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", on_get_saved_list)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", on_saved_list_rsp)

sys.taskInit(init_module)
