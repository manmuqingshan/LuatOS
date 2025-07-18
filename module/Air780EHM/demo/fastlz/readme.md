
## 演示功能概述

将使用Air780EHM核心板，演示FastLZ的压缩与解压缩的使用方法，实现读取文件系统中的文件，并演示压缩与解压缩的代码实现。

## 演示硬件环境

1、Air780EHM核心板一块

2、TYPE-C USB数据线一根

3、Air780EHM核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；
## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2007版本固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2007固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
[2025-06-30 14:10:53.447][000000001.239] I/user.原始数据长度	14525
[2025-06-30 14:10:53.469][000000001.241] I/user.压缩等级1：压缩后的数据长度	212
[2025-06-30 14:10:53.484][000000001.242] I/user.压缩等级1：解压后的的数据长度	14525
[2025-06-30 14:10:53.509][000000001.243] I/user.压缩等级1：解压后的数据与原始数据相同
[2025-06-30 14:10:54.166][000000002.244] I/user.压缩等级2：压缩后的数据长度	114
[2025-06-30 14:10:54.178][000000002.246] I/user.压缩等级2：解压后的数据长度	14525
[2025-06-30 14:10:54.191][000000002.247] I/user.压缩等级2：解压后的数据与原始数据相同

```