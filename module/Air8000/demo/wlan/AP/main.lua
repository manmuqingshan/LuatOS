
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

-- 如果无法使用AP功能，可以开启此功能升级WiFi固件版本后再次尝试
-- 升级完毕后最好取消调用，防止后期版本升级过高导致程序使用不稳定
-- require "check_wifi" 

function test_ap()
    log.info("执行AP创建操作")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            log.info("AP 创建成功，如果无法连接，需要将按照https://docs.openluat.com/air8000/luatos/app/updatwifi/update/ 升级固件")
            log.info("AP 创建成功，如果无法连接，请升级本仓库的最新core")
            break
        end
        sys.wait(1000)
    end
end

-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end)

sys.taskInit(function()
    log.info("开始AP 测试...")
    wlan.init()
    test_ap()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
