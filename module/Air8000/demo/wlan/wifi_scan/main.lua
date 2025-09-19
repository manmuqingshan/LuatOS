-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifiscan"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"

-- 如果无法使用此功能，可以开启此功能升级WiFi固件版本后再次尝试
-- 升级完毕后最好取消调用，防止后期版本升级过高导致程序使用不稳定
-- local exfotawifi = require("exfotawifi") 

function test_scan()
    while 1 do
        log.info("执行wifi扫描")
        wlan.scan()
        sys.wait(30 * 1000)
    end
end

function scan_done_handle()
    local result = wlan.scanResult()
    _G.scan_result = {}
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(_G.scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(_G.scan_result))
end

--  每隔6秒打印一次airlink统计数据, 调试用
sys.taskInit(function()
    while 1 do
        sys.wait(6000)
        airlink.statistics()
    end
end)

sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)

-- 在设备启动时检查网络状态
sys.taskInit(wait_ip_ready)

sys.taskInit(function()
    -- 稍微缓一下
    sys.wait(500)
    wlan.init()
    sys.wait(100)

    -- wifi扫描测试
    test_scan()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
