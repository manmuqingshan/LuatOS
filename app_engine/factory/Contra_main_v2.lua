--[[
@module  main
@summary Contra魂斗罗 exapp 入口（事件驱动，工厂 nes_key_app 管理 GPIO）
@version 3.2
@date    2026.05.30
@author  江访

本应用作为 exapp 运行在工厂框架之上：
  - 按键由工厂侧 nes_key_app 统一注册 GPIO，通过 sys.publish 发布全局事件
  - 本应用仅订阅 NES_DIR/NES_KEY/NES_CTRL/NES_COMBO 事件
  - 不操作 GPIO，不读全局变量
  - 启动后直接加载 data/Contra1.nes，触屏 + 实体按键双输入
  - 不需 sys.run()，工厂的 main.lua 已启动事件循环
]]

PROJECT = "Contra"
VERSION = "003.002.000"

log.info("main", PROJECT, VERSION)

require "nes_emulator"

log.info("main", "publish OPEN_NES_EMU_WIN")
sys.publish("OPEN_NES_EMU_WIN")
