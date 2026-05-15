## 功能模块介绍

1、main.lua：主程序入口；

2、helloworld_app.lua：每3秒打印1次hello world；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔三秒钟通过日志输出一次hello world；

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air780ehv/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV2.png)

1、Air780EHM/Air780EHV/Air780EGH核心板一块

2、TYPE-C USB数据线一根

3、Air780EHM/Air780EHV/Air780EGH核心板和数据线的硬件接线方式为

- Air780EHM/Air780EHV/Air780EGH核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 ON/OFF 拨动开关 拨到ON一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

2、[Air780EHM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/780ehm_version/)

3、[Air780EHV 最新版本的内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/700ech_version/)

4、[Air780EGH 最新版本的内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

5、本demo开发测试时使用的固件为[LuatOS-SOC_V2034_Air8000 版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-04-15 16:28:00.277][LTOS/N][000000201.039]:I/user.hello world
[2026-04-15 16:28:03.265][LTOS/N][000000204.039]:I/user.hello world
[2026-04-15 16:28:06.249][LTOS/N][000000207.039]:I/user.hello world
[2026-04-15 16:28:09.246][LTOS/N][000000210.040]:I/user.hello world
[2026-04-15 16:28:12.245][LTOS/N][000000213.040]:I/user.hello world
[2026-04-15 16:28:15.229][LTOS/N][000000216.040]:I/user.hello world
[2026-04-15 16:28:18.217][LTOS/N][000000219.041]:I/user.hello world

```
