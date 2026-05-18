--[[
@module  main
@summary 基础入门应用主入口
@version 1.0.0
@date    2026.05.17
@author  马亚丹
]]

PROJECT = "MY_APP_HELLO"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 加载窗口模块
require "my_win"

-- 发布消息触发窗口创建
sys.publish("OPEN_MY_WIN")

-- 进入事件循环（必需）
sys.run()