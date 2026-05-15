--[[
@module  main
@summary MJPG视频播放器 - 主程序入口
@version 1.0.0
@date    2026.04.10
@author  拓毅恒
@usage
MJPG格式视频播放器，支持逐帧播放、进度控制、帧率调节。
界面参考 videoplayer.html 设计，采用双页面结构：
1. 文件选择页面 - 选择MJPG视频文件
2. 播放控制页面 - 播放控制、进度调节、帧率设置
]]

PROJECT = "VIDEOPLAYER"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "player_win"

sys.publish("OPEN_VIDEOPLAYER_WIN")

sys.run()
