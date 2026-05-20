## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、tfcard_app.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能<br>
4、http_upload_file.lua：HTTP上传模块，实现网络检测与tf卡内大文件上传服务器的功能

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载tfcard_app模块（通过require "tfcard_app"）
- 加载http_download_file模块（通过require "http_download_file"）
- 加载http_upload_file模块（通过require "http_upload_file"）
- 最后运行sys.run()。

### 2、TF卡核心演示模块（tfcard_app.lua）

#### 文件系统管理

- SPI初始化与挂载：
  - 配置SPI接口参数（频率400kHz）
  - 挂载FAT32文件系统到`/sd`路径
  - 自动格式化检测与处理
- 空间信息获取：
  - 实时查询TF卡可用空间
  - 输出详细存储信息（总空间/剩余空间）
#### 文件操作
- 创建目录：io.mkdir("/sd/io_test")
- 创建/写入文件： io.open("/sd/io_test/boottime", "wb")
- 检查文件存在： io.exists(file_path)
- 获取文件大小：io.fileSize(file_path)
- 读取文件内容: io.open(file_path, "rb"):read("*a")
- 启动计数文件： 记录设备启动次数
- 文件追加： io.open(append_file, "a+")
- 按行读取： file:read("*l")
- 文件关闭： file:close()
- 文件重命名： os.rename(old_path, new_path)
- 列举目录： io.lsdir(dir_path)
- 删除文件： os.remove(file_path)
- 删除目录： io.rmdir(dir_path)

#### 结果处理

- 资源清理（卸载/SPI关闭）

### 3、HTTP下载功能 (http_download_file.lua)

#### 文件系统管理

- SPI初始化与挂载

#### 网络就绪检测

- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载/spi关闭）

### 4、HTTP上传功能 (http_download_file.lua)

#### 加载扩展库

- require("httpplus")

#### 网络就绪检测

- 1秒循环等待IP就绪

#### 文件系统管理

- SPI初始化与挂载

- 确认文件存在


#### 安全上传

- HTTP上传

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载/spi关闭）


## 演示硬件环境（二选一）

### 1、Air780EHM核心板演示环境

1、Air780EHM核心板一块(Air780EHM/780EGH/780EHV三种模块的核心板接线方式相同，这里以Air780EHM为例)

2、TYPE-C USB数据线一根

3、AirMICROSD_1010模块一个和SD卡一张

4、Air780EHM/780EGH/780EHV核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air780EHM核心板和AirMICROSD_1010模块接线方式

|   Air780EHM     |    AirMICROSD_1010    |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          3V3         |
|  GPIO8/SPI0_CS  |        spi_cs       |
|  SPI0_CLK       |        spi_clk,时钟       |
|  SPI0_MOSI      |  spi_mosi,主机输出,从机输入|
|  SPI0_MISO      |  spi_miso,主机输入,从机输出|

### 2、Air780EHM开发板演示环境

1、Air780EHM开发板一块(Air780EHM/780EGH/780EHV三种模块的开发板接线方式相同，这里以Air780EHM为例)

2、TYPE-C USB数据线一根

3、AirMICROSD_1010模块一个和SD卡一张

4、Air780EHM/780EGH/780EHV开发板和数据线的硬件接线方式为

- Air780EHM开发板通过TYPE-C USB口供电；（开发板USB旁边的开关拨到USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air780EHM开发板和AirMICROSD_1010模块接线方式
|   Air780EHM     |    AirMICROSD_1010    |
| --------------- | --------------------- |
|  GND(任意)      |          GND          |
|  VDD_EXT        |          3V3         |
|  GPIO16/SPI0_CS  |        spi_cs       |
|  SPI0_CLK       |        spi_clk,时钟       |
|  SPI0_MOSI      |  spi_mosi,主机输出,从机输入|
|  SPI0_MISO      |  spi_miso,主机输入,从机输出|

## 演示软件环境

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：
Air780EHM:https://docs.openluat.com/air780epm/luatos/firmware/version/
Air780EGH:https://docs.openluat.com/air780egh/luatos/firmware/version/
Air780EHV:https://docs.openluat.com/air780ehv/luatos/firmware/version/


## 演示核心步骤
1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板或开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
（1）TF卡初始化与挂载
[2026-05-15 09:39:06.348][000000000.421] I/user.main tfcard 001.999.000
[2026-05-15 09:39:06.352][000000000.434] I/user.exmux 开发板 DEV_BOARD_780_V1.3 初始化成功
[2026-05-15 09:39:06.354][000000000.435] I/user.exmux 设置引脚 cs1 (8) 为高电平
[2026-05-15 09:39:06.450][000000000.435] I/user.exmux 设置引脚 pwr1 (20) 为高电平
[2026-05-15 09:39:06.462][000000000.435] I/user.exmux 分组 spi0 打开成功
[2026-05-15 09:39:06.470][000000000.435] SPI_HWInit 445:APB MP 102400000
[2026-05-15 09:39:06.475][000000000.436] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 09:39:06.480][000000000.436] D/fatfs init sdcard at spi=0 cs=16
[2026-05-15 09:39:06.488][000000000.576] D/SPI_TF 卡容量 3932160KB
[2026-05-15 09:39:06.495][000000000.577] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 09:39:06.506][000000000.581] I/fatfs mount success at fat32
[2026-05-15 09:39:06.514][000000000.582] I/user.fatfs.mount 挂载成功 0
[2026-05-15 09:39:06.520][000000000.583] I/user.fatfs getfree {"free_sectors":7841920,"total_kb":3931584,"free_kb":3920960,"total_sectors":7863168}
[2026-05-15 09:39:06.526][000000000.584] I/user.fs lsmount [{"fs":"ec7xx","path":""},{"fs":"inline","path":"/lua/"},{"fs":"ram","path":"/ram/"},{"fs":"luadb","path":"/luadb/"},{"fs":"fatfs","path":"/sd"}]



（2）文件操作演示
[2026-05-15 09:39:06.530][000000000.584] I/user.文件操作 ===== 开始文件操作 =====
[2026-05-15 09:39:06.534][000000000.937] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2026-05-15 09:39:06.544][000000000.966] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2026-05-15 09:39:06.810][000000000.970] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2026-05-15 09:39:06.983][000000000.973] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2026-05-15 09:39:06.989][000000000.978] I/user.文件读取 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
[2026-05-15 09:39:06.996][000000000.983] I/user.启动计数 文件内容: 这是io库API文档示例的测试内容 十六进制: E8BF99E698AF696FE5BA93415049E69687E6A1A3E7A4BAE4BE8BE79A84E6B58BE8AF95E58685E5AEB9 82
[2026-05-15 09:39:07.011][000000000.984] I/user.启动计数 当前值: 0
[2026-05-15 09:39:07.016][000000000.984] I/user.启动计数 更新值: 1
[2026-05-15 09:39:07.091][000000001.020] I/user.文件写入 路径:/sd/io_test/boottime 内容: 1
[2026-05-15 09:39:07.095][000000001.052] I/user.文件创建 路径:/sd/io_test/test_a 初始内容:ABC
[2026-05-15 09:39:07.102][000000001.066] I/user.文件追加 路径:/sd/io_test/test_a 追加内容:def
[2026-05-15 09:39:07.112][000000001.071] I/user.文件验证 路径:/sd/io_test/test_a 内容:ABCdef 结果: 成功
[2026-05-15 09:39:07.121][000000001.114] I/user.文件创建 路径:/sd/io_test/testline 写入3行文本
[2026-05-15 09:39:07.136][000000001.119] I/user.按行读取 路径:/sd/io_test/testline 第1行: abc
[2026-05-15 09:39:07.147][000000001.119] I/user.按行读取 路径:/sd/io_test/testline 第2行: 123
[2026-05-15 09:39:07.154][000000001.120] I/user.按行读取 路径:/sd/io_test/testline 第3行: wendal
[2026-05-15 09:39:07.159][000000001.131] I/user.os.rename 文件重命名成功 原路径:/sd/io_test/test_a 新路径:/sd/io_test/renamed_file.txt
[2026-05-15 09:39:07.268][000000001.138] D/fatfs f_open /io_test/test_a 4
[2026-05-15 09:39:07.273][000000001.138] D/vfs fopen /sd/io_test/test_a r not found
[2026-05-15 09:39:07.279][000000001.138] I/user.验证结果 重命名验证成功 新文件存在 原文件不存在
[2026-05-15 09:39:07.285][000000001.138] I/user.目录操作 ===== 开始目录列举 =====
[2026-05-15 09:39:07.291][000000001.150] I/user.fs lsdir [{"name":"boottime","size":1,"type":0},{"name":"testline","size":15,"type":0},{"name":"renamed_file.txt","size":6,"type":0}]
[2026-05-15 09:39:07.296][000000001.167] I/user.os.remove 文件删除成功 路径:/sd/io_test/renamed_file.txt
[2026-05-15 09:39:07.302][000000001.170] D/fatfs f_open /io_test/renamed_file.txt 4
[2026-05-15 09:39:07.308][000000001.170] D/vfs fopen /sd/io_test/renamed_file.txt r not found
[2026-05-15 09:39:07.313][000000001.171] I/user.验证结果 renamed_file.txt文件删除验证成功
[2026-05-15 09:39:07.319][000000001.189] I/user.os.remove testline文件删除成功 路径:/sd/io_test/testline
[2026-05-15 09:39:07.324][000000001.192] D/fatfs f_open /io_test/testline 4
[2026-05-15 09:39:07.329][000000001.192] D/vfs fopen /sd/io_test/testline r not found
[2026-05-15 09:39:07.336][000000001.192] I/user.验证结果 testline文件删除验证成功
[2026-05-15 09:39:07.763][000000001.307] I/user.os.remove 文件删除成功 路径:/sd/io_test/boottime
[2026-05-15 09:39:07.770][000000001.310] D/fatfs f_open /io_test/boottime 4
[2026-05-15 09:39:07.778][000000001.310] D/vfs fopen /sd/io_test/boottime r not found
[2026-05-15 09:39:07.786][000000001.310] I/user.验证结果 boottime文件删除验证成功
[2026-05-15 09:39:07.793][000000001.329] I/user.io.rmdir 目录删除成功 路径:/sd/io_test
[2026-05-15 09:39:07.798][000000001.331] D/fatfs f_open /io_test 4
[2026-05-15 09:39:07.806][000000001.331] D/vfs fopen /sd/io_test r not found
[2026-05-15 09:39:07.814][000000001.332] I/user.验证结果 目录删除验证成功
[2026-05-15 09:39:07.821][000000001.333] I/user.文件操作 ===== 文件操作完成 =====
[2026-05-15 09:39:07.826][000000001.334] I/user.结束 开始执行关闭操作...
[2026-05-15 09:39:07.831][000000001.334] I/user.文件系统 卸载成功
[2026-05-15 09:39:07.841][000000001.334] I/user.SPI接口 已关闭
[2026-05-15 09:39:07.858][000000001.334] I/user.exmux 设置引脚 cs1 (8) 为低电平
[2026-05-15 09:39:07.864][000000001.335] I/user.exmux 设置引脚 pwr1 (20) 为低电平
[2026-05-15 09:39:07.870][000000001.335] I/user.exmux 分组 spi0 关闭成功


（3）网络连接与HTTP下载
[2026-05-15 09:41:48.749][000000000.404] I/user.main tfcard 001.999.000
[2026-05-15 09:41:48.755][000000000.415] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:49.346][000000001.415] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:49.761][000000002.416] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:50.712][000000003.417] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:51.707][000000004.418] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:52.700][000000005.419] W/user.HTTP下载 等待网络连接 1 1
[2026-05-15 09:41:53.096][000000005.680] D/mobile cid1, state0
[2026-05-15 09:41:53.102][000000005.681] D/mobile bearer act 0, result 0
[2026-05-15 09:41:53.108][000000005.684] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 09:41:53.112][000000005.685] I/user.HTTP下载 网络已就绪 1 1
[2026-05-15 09:41:53.120][000000005.686] I/user.exmux 开发板 DEV_BOARD_780_V1.3 初始化成功
[2026-05-15 09:41:53.127][000000005.686] I/user.exmux 设置引脚 cs1 (8) 为高电平
[2026-05-15 09:41:53.135][000000005.687] I/user.exmux 设置引脚 pwr1 (20) 为高电平
[2026-05-15 09:41:53.145][000000005.687] I/user.exmux 分组 spi0 打开成功
[2026-05-15 09:41:53.153][000000005.688] SPI_HWInit 445:APB MP 102400000
[2026-05-15 09:41:53.159][000000005.688] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 09:41:53.170][000000005.689] D/fatfs init sdcard at spi=0 cs=16
[2026-05-15 09:41:53.175][000000005.707] D/SPI_TF 卡容量 3932160KB
[2026-05-15 09:41:53.179][000000005.708] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 09:41:53.182][000000005.712] I/fatfs mount success at fat32
[2026-05-15 09:41:53.189][000000005.712] I/user.HTTP下载 开始下载任务
[2026-05-15 09:41:53.196][000000005.718] dns_run 676:cdn.openluat-erp.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 09:41:53.202][000000005.720] D/mobile TIME_SYNC 0 tm 1778809312
[2026-05-15 09:41:53.207][000000005.846] dns_run 693:dns all done ,now stop
[2026-05-15 09:43:08.846][000000081.562] I/http http close c1163d4
[2026-05-15 09:43:08.851][000000081.565] I/user.HTTP下载 下载完成 success 200 
[2026-05-15 09:43:08.853][000000081.565] {"x-oss-hash-crc64ecma":"7570337686322137116","x-oss-server-time":"96","x-oss-object-type":"Normal","Content-Length":"3389723","Via":"cache45.l2cn8003[252,252,200-0,M], cache46.l2cn8003[253,0], kunlun8.cn9405[325,325,200-0,M], kunlun10.cn9405[331,0]","x-oss-cdn-auth":"success","Date":"Fri, 15 May 2026 01:41:54 GMT","x-oss-request-id":"6A0679E28A3C5F3032719295","Content-MD5":"Ap894+Aw36xpOHjjgfW0Cw==","Last-Modified":"Wed, 03 Sep 2025 07:26:20 GMT","Connection":"close","Server":"Tengine","ETag":"\"029F3DE3E030DFAC693878E381F5B40B\"","Timing-Allow-Origin":"*","X-Swift-CacheTime":"3600","Accept-Ranges":"bytes","x-oss-storage-class":"Standard","Content-Type":"application/octet-stream","X-Swift-SaveTime":"Fri, 15 May 2026 01:41:54 GMT","X-Cache":"MISS TCP_MISS dirn:-2:-2","Ali-Swift-Global-Savetime":"1778809314","EagleId":"6ae3669e17788093139188470e"}
[2026-05-15 09:43:08.861][000000081.565]  3389723
[2026-05-15 09:43:08.865][000000081.568] I/user.HTTP下载 文件大小验证 预期: 3389723 实际: 3389723
[2026-05-15 09:43:08.869][000000081.568] I/user.HTTP下载 资源清理完成
[2026-05-15 09:43:08.872][000000081.569] I/user.exmux 设置引脚 cs1 (8) 为低电平
[2026-05-15 09:43:08.874][000000081.569] I/user.exmux 设置引脚 pwr1 (20) 为低电平
[2026-05-15 09:43:08.877][000000081.570] I/user.exmux 分组 spi0 关闭成功


（4）网络连接与HTTP上传
[2026-05-15 09:45:06.863][000000000.443] I/user.main tfcard 001.999.000
[2026-05-15 09:45:06.867][000000000.465] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:07.365][000000001.465] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:08.240][000000002.466] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:09.234][000000003.467] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:10.244][000000004.468] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:11.240][000000005.469] W/user.HTTP上传 等待网络连接 1 1
[2026-05-15 09:45:11.537][000000005.699] D/mobile cid1, state0
[2026-05-15 09:45:11.539][000000005.700] D/mobile bearer act 0, result 0
[2026-05-15 09:45:11.542][000000005.700] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-15 09:45:11.546][000000005.704] I/user.HTTP上传 网络已就绪 1 1
[2026-05-15 09:45:11.549][000000005.705] I/user.exmux 开发板 DEV_BOARD_780_V1.3 初始化成功
[2026-05-15 09:45:11.551][000000005.705] I/user.exmux 设置引脚 cs1 (8) 为高电平
[2026-05-15 09:45:11.555][000000005.706] I/user.exmux 设置引脚 pwr1 (20) 为高电平
[2026-05-15 09:45:11.558][000000005.706] I/user.exmux 分组 spi0 打开成功
[2026-05-15 09:45:11.561][000000005.706] SPI_HWInit 445:APB MP 102400000
[2026-05-15 09:45:11.565][000000005.707] SPI_HWInit 556:spi0 speed 2000000,1994805,154
[2026-05-15 09:45:11.570][000000005.708] D/fatfs init sdcard at spi=0 cs=16
[2026-05-15 09:45:11.572][000000005.727] D/SPI_TF 卡容量 3932160KB
[2026-05-15 09:45:11.575][000000005.728] D/SPI_TF sdcard init OK OCR:0xc0ff8000!
[2026-05-15 09:45:11.580][000000005.732] I/fatfs mount success at fat32
[2026-05-15 09:45:11.582][000000005.735] I/user.HTTP上传 准备上传文件 /sd/3_23MB.bin 大小: 3389723 字节
[2026-05-15 09:45:11.584][000000005.735] I/user.HTTP上传 开始上传任务
[2026-05-15 09:45:11.586][000000005.741] D/socket connect to airtest.luatos.com,443
[2026-05-15 09:45:11.589][000000005.741] dns_run 676:airtest.luatos.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-05-15 09:45:11.592][000000005.743] D/mobile TIME_SYNC 0 tm 1778809511
[2026-05-15 09:45:12.276][000000006.498] dns_run 693:dns all done ,now stop
[2026-05-15 09:45:12.947][000000007.180] I/zbuff create large size: 128 kbyte, trigger force GC
[2026-05-15 09:45:33.108][000000027.331] I/user.httpplus 服务器已完成响应
[2026-05-15 09:45:33.114][000000027.334] I/user.HTTP上传 上传完成 success 200
[2026-05-15 09:45:33.118][000000027.335] I/user.HTTP上传 服务器响应头 {"Content-Length":"257","Date":"Fri, 15 May 2026 01:45:33 GMT","Connection":"close","Server":"nginx/1.28.2","Vary":"Access-Control-Request-Headers","Content-Type":"application/x-www-form-urlencoded;charset=UTF-8"}
[2026-05-15 09:45:33.121][000000027.336] I/user.HTTP上传 服务器响应体长度 257
[2026-05-15 09:45:33.126][000000027.336] I/user.HTTP上传 服务器响应内容 {"info":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add","code":0,"trace":"iot->iam-server./iam/tenant/getbyoid/6268048492107342913./iot/luat_test_file/add trcace:clear 1 temp suc infos.","log":"^^^","value":"上传成功"}
[2026-05-15 09:45:33.134][000000027.337] I/user.HTTP上传 资源清理完成
[2026-05-15 09:45:33.143][000000027.337] I/user.exmux 设置引脚 cs1 (8) 为低电平
[2026-05-15 09:45:33.147][000000027.338] I/user.exmux 设置引脚 pwr1 (20) 为低电平
[2026-05-15 09:45:33.151][000000027.338] I/user.exmux 分组 spi0 关闭成功

```

## **异常处理**

1、使用合宙开发板时，如出现TF卡初始化失败的情况，请使用exmux扩展库的setup函数初始化外设分组开关状态，使用open函数打开外设分组，并跳转至exmux扩展库介绍文档中了解I2C/SPI总线上拉问题；https://docs.openluat.com/osapi/ext/exmux/

2、使用自己制作的板子时，如出现TF卡初始化失败的情况，请根据各型号文档中”硬件设计资料“的I2C和SPI板块”常见的坑“栏目中的经验，检查板子上的I2C/SPI总线是正常上拉；也可使用exmux库来管理i2c和spi总线的上拉状态，详情请参考exmux扩展库介绍文档。