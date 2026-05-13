--[[
@module  main
@summary Modbus TCP 主站应用 - 主程序入口
@version 1.0.0
@date    2026.05.11
@author  马梦阳
@usage

]]

PROJECT = "MODBUS_TCP_MASTER"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

require "modbus_win"

sys.publish("OPEN_MODBUS_WIN")

sys.run()
