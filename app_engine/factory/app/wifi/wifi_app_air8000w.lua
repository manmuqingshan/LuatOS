--[[
@module  wifi_app
@summary WiFi应用模块（Air8000W/Air8101/PC 业务逻辑层，事件驱动）
@version 1.2
@date    2026.05.19
@author  江访
@usage
== 状态机（从初始化到联网的完整链路）==
 自动扫描 → WIFI_SCAN_DONE
   → 连接热点 → exnetif.set_priority_order
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
local common = require "wifi_app_common"
local exnetif = require "exnetif"

local SCAN_TIMEOUT = 10000      -- WiFi扫描超时时间（毫秒）
local UPDATE_INTERVAL = 5000    -- 网络信息更新间隔（毫秒）
local CONNECTIVITY_TIMEOUT = 30000 -- 联网连通性确认超时（毫秒）

-- WiFi当前状态
local wifi_state = {
    connected = false,           -- L2: 是否与AP关联成功
    ready = false,               -- L3: 是否获取到IP
    connectivity_verified = false,-- Internet: NTP同步是否成功
    current_ssid = "",           -- 当前连接的SSID
    rssi = "--",                 -- 信号强度
    ip = "--",                   -- IP地址
    netmask = "--",              -- 子网掩码
    gateway = "--",              -- 网关
    bssid = "--",                -- AP的MAC地址
    scan_results = {}            -- 扫描结果列表
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

local scan_timer = nil           -- 扫描超时定时器（也为nil时表示空闲可扫描）
local update_timer = nil         -- 网络信息更新定时器
local last_connect = nil         -- 上次连接状态
local disconnect_reason = nil    -- 断开连接原因（用于区分"配置前断开"和真实断开）
local user_disconnect = false    -- 用户主动断开标记
local user_connect = false       -- 用户主动连接标记

--[[
更新WiFi状态并发布事件
@param table status - 包含要更新的状态字段
]]
local function update_status(status)
    if not status then
        log.error("wifi_app", "更新WiFi状态时，状态对象为空")
        return
    end
    for k, v in pairs(status) do
        wifi_state[k] = v
    end
    common.update_status(wifi_state, saved_config)
end

--[[
刷新并更新网络信息（IP、网关、子网掩码等）
]]
local function refresh_net_info()
    common.refresh_network_info(wifi_state)
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
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 3)
        last_connect = "CONNECTED"
        user_connect = false

        -- 启动定时刷新网络信息
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        update_timer = sys.timerLoopStart(refresh_net_info, UPDATE_INTERVAL)

    elseif event == "DISCONNECTED" then
        -- user_connect 为 true 说明是 on_connect_request 的连接失败
        if user_connect then
            log.info("wifi_app", "用户发起的连接失败，重置状态以允许再次弹窗")
            last_connect = nil
        elseif last_connect == "DISCONNECTED" then
            -- 已断开状态，跳过重复事件（防抖）
            log.info("wifi_app", "已断开状态，跳过重复事件")
            return
        end

        -- disconnect_reason == "config" 说明是 on_connect_request 中先 exnetif.close 产生的
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
        local reason_name = common.resolve_disconnect_reason(data)
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
@param string ip - IP地址
@param number adapter - 网卡适配器
]]
local function handle_ip_ready(ip, adapter)
    common.handle_ip_ready(ip, adapter, wifi_state, refresh_net_info)
    -- IP就绪后，启动联网连通性确认（等待NTP同步）
    sys.taskInit(function()
        common.start_connectivity_verification(wifi_state, CONNECTIVITY_TIMEOUT)
    end)
end

--[[
处理IP丢失事件
@param number adapter - 网卡适配器
]]
local function handle_ip_lose(adapter)
    common.handle_ip_lose(adapter, wifi_state)
    wifi_state.connectivity_verified = false
end

--[[
处理WLAN_SCAN_DONE事件
]]
local function handle_scan_done()
    local scan_ref = {}
    scan_ref[1] = scan_timer
    common.handle_scan_done(wifi_state, scan_ref)
    scan_timer = scan_ref[1]
end

--[[
处理扫描超时事件
]]
local function handle_scan_timeout()
    scan_timer = nil
    common.handle_scan_timeout({})
end

--[[
自动扫描并验证保存的SSID是否在附近
@return table {verified, ssid, signal} - 验证结果
]]
local function auto_scan_verify()
    return common.auto_scan_and_verify(saved_config)
end

--[[
运行开机自动连接（选择信号最强的已保存网络连接）
]]
local function run_auto_connect()
    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi开关已关闭，跳过自动连接")
        return
    end
    if wifi_state.connected then
        log.info("wifi_app", "已连接WiFi，刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    log.info("wifi_app", "开始执行开机自动连接（选择信号最强的已保存网络）")
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
        log.info("wifi_app", "自动连接请求发送成功")
    else
        log.info("wifi_app", "附近没有已保存网络，等待手动连接")
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
    common.on_storage_set_enabled_rsp(data, saved_config)
end

--[[
处理WIFI_ENABLE_REQ事件（WiFi开关切换）
@param table data - 包含enabled字段的数据
]]
local function on_enable_request(data)
    local enabled = data.enabled
    log.info("wifi_app", "收到开关请求:", enabled)

    if saved_config then
        saved_config.wifi_enabled = enabled
    end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", {enabled = enabled})

    -- PC 模拟器路径
    if _G.model_str:find("PC") then
        if not enabled then
            wifi_state.connected = false
            wifi_state.ready = false
            wifi_state.current_ssid = ""
            wifi_state.rssi = "--"
            wifi_state.ip = "--"
            wifi_state.netmask = "--"
            wifi_state.gateway = "--"
            wifi_state.bssid = "--"
            wifi_state.connectivity_verified = false
            update_status(wifi_state)
        else
            log.info("wifi_app", "正在开启WiFi网卡")
            if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
                if wifi_state.connected then
                    log.info("wifi_app", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                    sys.taskInit(run_auto_connect)
                end
            end
        end
        return
    end

    -- 真机关闭
    if not enabled then
        log.info("wifi_app", "正在关闭WiFi网卡")
        exnetif.close(nil, socket.LWIP_STA)
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
        if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
            if wifi_state.connected then
                log.info("wifi_app", "已连接WiFi，只进行扫描")
                sys.publish("WIFI_SCAN_REQ")
            else
                log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                sys.taskInit(run_auto_connect)
            end
        end
    end
end

--[[
处理WIFI_SCAN_REQ事件（开始扫描WiFi热点）
]]
local function on_scan_request()
    log.info("wifi_app", "收到扫描请求")

    if scan_timer then
        log.info("wifi_app", "扫描已在进行中，跳过重复请求")
        return
    end

    -- PC 模拟器：返回模拟数据
    if _G.model_str:find("PC") then
        sys.publish("WIFI_SCAN_STARTED")
        sys.taskInit(function()
            sys.wait(1500)
            local mock_results = {
                { ssid = "ChinaNet-5G", rssi = -45, channel = 149 },
                { ssid = "TP-LINK_ABC", rssi = -62, channel = 6 },
                { ssid = "CMCC-8888", rssi = -58, channel = 11 },
                { ssid = "HUAWEI-1234", rssi = -70, channel = 1 }
            }
            wifi_state.scan_results = mock_results
            sys.publish("WIFI_SCAN_DONE", mock_results)
            scan_timer = nil
        end)
        return
    end

    -- 真机扫描
    wlan.init()
    wlan.scan()
    scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
    sys.publish("WIFI_SCAN_STARTED")
end

--[[
处理WIFI_CONNECT_REQ事件（连接WiFi热点）
@param table data - 包含ssid, password, advanced_config字段的数据
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

    -- PC 模拟器：模拟连接过程
    if _G.model_str:find("PC") then
        sys.publish("WIFI_CONNECTING", ssid)
        sys.taskInit(function()
            sys.wait(2000)
            local success = math.random(100) > 20
            if success then
                wifi_state.connected = true
                wifi_state.current_ssid = ssid
                wifi_state.rssi = tostring(-50 - math.random(20))
                wifi_state.bssid = string.format("A0:B1:C2:D3:E4:%02X", math.random(255))
                wifi_state.ip = string.format("192.168.1.%d", math.random(2, 254))
                wifi_state.netmask = "255.255.255.0"
                wifi_state.gateway = "192.168.1.1"
                wifi_state.ready = true
                wifi_state.connectivity_verified = false
                sys.publish("WIFI_CONNECTED", ssid)
                sys.wait(500)
                update_status(wifi_state)
            else
                wifi_state.connected = false
                wifi_state.current_ssid = ""
                wifi_state.ready = false
                wifi_state.ip = "--"
                wifi_state.netmask = "--"
                wifi_state.gateway = "--"
                wifi_state.bssid = "--"
                wifi_state.rssi = "--"
                wifi_state.connectivity_verified = false
                update_status(wifi_state)
                sys.publish("WIFI_DISCONNECTED", "密码错误或连接超时", -1)
            end
        end)
        return
    end

    -- 真机连接
    sys.publish("WIFI_CONNECTING", ssid)
    disconnect_reason = "config"
    exnetif.close(nil, socket.LWIP_STA)

    -- 构建exnetif配置
    local wifi_config = { ssid = ssid, password = password }
    if saved_config then
        if saved_config.need_ping ~= nil then
            wifi_config.need_ping = saved_config.need_ping
        end
        if saved_config.local_network_mode ~= nil then
            wifi_config.local_network_mode = saved_config.local_network_mode
        end
        if saved_config.ping_ip ~= nil and saved_config.ping_ip ~= "" then
            wifi_config.ping_ip = saved_config.ping_ip
        end
        if saved_config.ping_time ~= nil and saved_config.ping_time ~= "" then
            wifi_config.ping_time = tonumber(saved_config.ping_time) or 10000
        end
        if saved_config.auto_socket_switch ~= nil then
            wifi_config.auto_socket_switch = saved_config.auto_socket_switch
        end
    end

    local result = exnetif.set_priority_order({ { WIFI = wifi_config } })

    if result then
        log.info("wifi_app", "WiFi连接参数配置成功")
    else
        log.error("wifi_app", "WiFi连接参数配置失败")
        sys.publish("WIFI_DISCONNECTED", "连接参数配置失败", -5)
    end
end

--[[
处理WIFI_DISCONNECT_REQ事件（用户主动断开连接）
]]
local function on_disconnect_request()
    log.info("wifi_app", "收到断开请求")
    user_disconnect = true

    if _G.model_str:find("PC") then
        wifi_state.connected = false
        wifi_state.current_ssid = ""
        wifi_state.ready = false
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        wifi_state.rssi = "--"
        wifi_state.connectivity_verified = false
        update_status(wifi_state)
        sys.publish("WIFI_SCAN_REQ")
        return
    end

    exnetif.close(nil, socket.LWIP_STA)
    -- disconnect_reason 不在这里设值，避免与 on_connect_request 的 "config" 冲突。
    -- WLAN_STA_INC DISCONNECTED 事件会异步到来，
    -- handle_sta_event 通过 user_disconnect 标记判断是用户主动断开。
end

--[[
处理WIFI_GET_STATUS_REQ事件
]]
local function on_get_status()
    common.on_get_status_req(wifi_state, saved_config)
end

--[[
处理WIFI_GET_CONFIG_REQ事件
]]
local function on_get_config()
    common.on_get_config_req(saved_config)
end

--[[
处理WIFI_GET_SAVED_LIST_REQ事件
]]
local function on_get_saved_list()
    common.on_get_saved_list_req(saved_config)
end

--[[
处理WIFI_STORAGE_GET_SAVED_LIST_RSP事件
]]
local function on_saved_list_rsp(data)
    common.on_storage_get_saved_list_rsp(data)
end

--[[
处理WIFI_STORAGE_INIT_RSP事件
]]
local function on_storage_ready(data)
    common.on_storage_init_rsp(data)
end

--[[
初始化模块
]]
local function init()
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_ready)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

-- 订阅所有事件（放在文件末尾，确保所有函数都已定义）
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

sys.taskInit(init)
