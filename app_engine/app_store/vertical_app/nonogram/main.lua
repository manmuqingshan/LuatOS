--[[
@module  main
@summary 数织游戏 - 主程序入口
@version 1.0.0
@date    2026.05.13
@usage

]]

PROJECT = "NONOGRAM"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

require "nonogram_win"

sys.publish("OPEN_NONOGRAM_WIN")

sys.run()
