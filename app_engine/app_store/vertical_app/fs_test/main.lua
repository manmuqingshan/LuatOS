--[[
@module  main
@summary 多存储文件IO测试应用入口（exwin架构）
@version 1.0.0
@date    2026.05.13
]]

PROJECT = "FS_TEST"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "fs_test_win"

sys.publish("OPEN_FS_TEST_WIN")

sys.run()
