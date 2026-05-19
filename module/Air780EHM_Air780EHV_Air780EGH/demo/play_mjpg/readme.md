# MJPG视频播放器介绍

## 项目概述

本项目是基于 Air780EHM/Air780EHV/Air780EGH 的视频播放演示demo，实现了两种视频播放场景（二选一）：播放本地烧录的视频、以及播放从服务器下载的视频。

## 文件结构

- main.lua: 主程序入口，支持二选一演示模式
- lcd_drv.lua: LCD驱动初始化模块
- mjpg_player.lua: 播放本地烧录的视频功能模块
- mjpg_player_server.lua: 播放从服务器下载的视频功能模块
- fly_man_80.mjpg: 示例视频文件

## 功能模块说明

### 场景一：本地烧录的视频（默认启用）

**使用方式**：
- 在 main.lua 中启用 `require "mjpg_player"`
- 将 `fly_man_80.mjpg` 和代码一起烧录到固件中
- 上电后自动开始播放

### 场景二：从服务器下载的视频

**使用方式**：

- 需要插入 SIM 卡并连接网络
- 在 main.lua 中启用 `require "mjpg_player_server"`
- 在 main.lua 中注释掉 `require "mjpg_player"`
- 上电后自动下载并播放

## 演示硬件环境

1、Air780EHM/Air780EHV/Air780EGH开发板一块+LCD屏幕

![alt text](https://docs.openLuat.com/cdn/image/780EXX_AirLCD1010.jpg )

或者Air780EHM/Air780EHV/Air780EGH核心板+AirLCD_1010 LCD配件板

![alt text](https://docs.openluat.com/air780ehv/luatos/app/accessory/AirLCD_1010/lcd/image/image1.png )

Air780EHM/Air780EHV/Air780EGH核心板和AirLCD_1010配件板的硬件接线方式为:

|  Air780EHM/Air780EHV/Air780EGH核心板   | AirLCD_1010配件板 |
| --------------- | -----------------   |
| 53/LCD_CLK      | SCLK/CLK            |
| 52/LCD_CS       | CS                  |
| 49/LCD_RST      | RES/RST             |
| 50/LCD_SDA      | SDA/MOS             |
| 51/LCD_RS       | DC/RS               |
| 22/GPIO1        | BLK                 |
| 3V3             | VCC                 |
| 67/I2C1_SCL     | SCL                 |
| 66/I2C1_SDA     | SDA                 |
| 20/GPIO24       | INT                 |
| GND             | GND                 |

2、TYPE-C USB数据线一根

- Air780EHM/Air780EHV/Air780EGH核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/common/Luatools/)

2、[Air780EHM固件](https://docs.openluat.com/air780epm/luatos/firmware/780ehm_version/)，选择支持AirUI功能的固件。

3、[Air780EHV固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，选择支持AirUI功能的固件。

4、[Air780EGH固件](https://docs.openluat.com/air780egh/luatos/firmware/780egg%26780egh_version/)，选择支持AirUI功能的固件。

5、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/play_mjpg)

- 准备好软件环境之后，接下来查看如何[使用 LuaTools 烧录软件](https://docs.openluat.com/air780epm/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到 Air780EHM/Air780EHV/Air780EGH 核心板中

6、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、根据需求配置演示功能：

   - 编辑main.lua文件，选择需要演示的功能
   - 功能一（本地烧录的视频）：取消注释 `require "mjpg_player"`，注释掉 `require "mjpg_player_server"`
   - 功能二（从服务器下载的视频）：注释掉 `require "mjpg_player"`，取消注释 `require "mjpg_player_server"`

3、功能一需要烧录视频文件：

   - 将 `fly_man_80.mjpg` 放入项目目录
   - 使用 Luatools 将视频文件打包到固件中
   - 烧录固件到设备

4、功能二需要插入SIM卡并连接网络

5、Luatools烧录内核固件和修改后的demo脚本代码

6、烧录成功后，自动开机运行

7、运行程序，观察日志输出了解系统状态

### 功能一：本地烧录的视频

当设备启动并初始化完成后，自动加载并播放视频文件。

类似以下日志：

``` lua
I/user.main PLAY_MJPG 001.999.000
I/user.播放器 初始化LCD和AirUI...
I/user.lcd.init true
I/user.airui init success 320 480
I/user.播放器 准备播放视频...
I/user.播放器 LCD尺寸: 320 x 480
I/user.播放器 视频实际分辨率: 160 x 160
I/user.播放器 视频显示位置: 80 160
I/user.播放器 视频组件创建成功
I/user.播放器 背光已开启
I/user.播放器 视频开始播放
```

### 功能二：从服务器下载并播放视频

设备启动后连接网络，下载视频文件后自动播放。

类似以下日志：

``` lua
I/user.播放器 初始化LCD和AirUI...
I/user.lcd.init true
I/user.airui init success 320 480
I/user.播放器 准备播放视频...
I/user.播放器 从服务器下载视频: https://appstoreoss.luatos.com/iot-apps/res/100197/video_160x160.mjpg
I/user.播放器 等待网络连接...
I/user.播放器 网络已就绪
I/user.播放器 开始下载...
I/user.播放器 下载完成, 大小: 424469 字节
I/user.播放器 LCD尺寸: 320 x 480
I/user.播放器 视频实际分辨率: 160 x 160
I/user.播放器 视频显示位置: 80 160
I/user.播放器 视频组件创建成功
I/user.播放器 背光已开启
I/user.播放器 视频开始播放
```

## 视频格式要求

- **格式**：MJPG (Motion JPEG)
- **分辨率**：不超过 320x480（LCD 分辨率）
- **帧率**：默认 15fps，可通过 `VIDEO_FPS` 变量调整
