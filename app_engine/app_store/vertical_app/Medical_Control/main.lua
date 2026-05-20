
--[[
@module  Medical_Control
@summary  智能医疗设备中控系统 - 患者监护系统
@version 1.0
@date    2026-05-12
@author  马亚丹
]]
PROJECT = "Medical_Control"
VERSION = "001.001.000"

log.info("main", PROJECT, VERSION)

require "medical_control_win"

sys.publish("OPEN_MEDICAL_CONTROL_WIN")
sys.run()
