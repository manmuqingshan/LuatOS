-- main.lua - 智慧校车刷卡系统主入口
PROJECT = "SCHOOL_BUS"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

require "school_bus_win"

-- 打开校车系统窗口
sys.publish("OPEN_SCHOOL_BUS_WIN")

sys.run()