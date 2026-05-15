## 功能模块介绍

1、main.lua：主程序入口；

2、sip_app_main.lua：sip主入口;

3、sip_app_key.lua：按键相关处理;

4、audio_drv.lua：音频驱动模块；

5、netdrv_4g.lua：4g网络模块

6、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块

7、netdrv_multiple.lua：多网卡（4G网卡、STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块


## 演示功能概述

使用Air780EHV开发板测试sip功能

1、4g联网测试sip功能；

2、以太网联网测试sip功能；

3、多网融合测试sip功能
## 演示硬件环境

[](https://docs.openluat.com/air8000/luatos/app/image/eth_sip.jpg)

1、Air780EHV开发板一块+物联网一张+4g天线一根+网线一根：

* 天线装到开发板上对应位置

* 测试4g联网时sip功能：将物联网卡插入开发板的sim卡槽

* 测试以太网联网时sip功能：拔出物联网卡，网线一端连到开发板网口，网线另一端连到路由器网口

2、TYPE-C USB数据线一根，Air780EHV开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[必须使用Air780EHV V2034或者更高版本带audio的固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2034-1固件对比验证）

3、PC端下载MicroSIP软件，用于测试sip通话功能

## 演示核心步骤

1、搭建好硬件环境

2、在main.lua中选择要测试的网卡场景，如：选择测试以太网联网测试sip通话的场景，则注释掉4g网卡相关代码，打开以太网网卡相关代码，即在netdrv_device.lua脚本中require "netdrv_eth_spi"；

3、烧录内核固件和sip相关demo成功后，自动开机运行；

4、打开MicroSIP，输入sip_app.lua中SIP_CONFIG配置的sip服务器地址，端口，域名，注意：用户名和密码按实际填，尤其是用户名不能与脚本中一样，例如脚本中用户名为1000001，MicroSIP软件用户名不可再填100001；

5、可以看到代码运行结果如下：

以下是使用sip demo演示的日志

日志中如果出现"SIP 服务已就绪"，就可以开始测试通话，收到来电，按boot键接听，通话建立，日志如下：

```
[2026-05-15 15:37:37.771][000000006.473] I/user.sip_app_key SIP应用已初始化
[2026-05-15 15:37:37.772][000000006.536] I/user.sip req NOTIFY from 180.152.6.34 8910
[2026-05-15 15:37:40.851][000000009.749] I/user.sip req INVITE from 180.152.6.34 8910
[2026-05-15 15:37:40.857][000000009.750] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1778815043 1778815044 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 15618 RTP/AVP 8 0 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-15 15:37:40.867][000000009.758] I/user.JQsip emit_event call incoming function
[2026-05-15 15:37:40.871][000000009.758] I/user.exsip event: call action: incoming
[2026-05-15 15:37:40.877][000000009.759] I/user.sip_callback STATE_READY call incoming table: 0C7C2B08 nil
[2026-05-15 15:37:40.881][000000009.759] I/user.sip_callback call event sub_event= incoming
[2026-05-15 15:37:40.886][000000009.760] I/user.sip_callback 来电: "Extension 100000" <sip:100000@180.152.6.34>;tag=59pp2781KcZ7Q cbf3a9b0-cad3-123f-2697-441a4c127a21 sip:100001@192.168.1.101:5062;received=180.171.81.183:11776 table: 0C7C5740 table: 0C7C43F0
[2026-05-15 15:37:40.893][000000009.760] I/user.JQsip emit_event call ringing function
[2026-05-15 15:37:40.897][000000009.761] I/user.exsip event: call action: ringing
[2026-05-15 15:37:40.901][000000009.761] I/user.sip_callback STATE_READY call ringing table: 0C7C2720 nil
[2026-05-15 15:37:40.908][000000009.762] I/user.sip_callback call event sub_event= ringing
[2026-05-15 15:37:40.913][000000009.762] I/user.sip_callback 对方响铃中
[2026-05-15 15:37:40.917][000000009.762] I/user.JQsip emit_event media offer function
[2026-05-15 15:37:40.921][000000009.763] I/user.exsip event: media action: offer
[2026-05-15 15:37:40.927][000000009.764] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100000" <sip:100000@180.152.6.34>;tag=59pp2781KcZ7Q
[2026-05-15 15:37:40.931][000000009.764] I/user.sip_app_main_task_func after process STATE_INCOMING
[2026-05-15 15:37:40.936][000000009.765] I/user.sip_app_key 呼入中，来电号码： 100000
[2026-05-15 15:37:41.519][000000010.411] I/user.Ethernet网卡开始PING
[2026-05-15 15:37:41.523][000000010.411] I/user.dns_request Ethernet true
[2026-05-15 15:37:41.528][000000010.413] D/net adapter 4 connect 223.5.5.5:80 TCP
[2026-05-15 15:37:41.550][000000010.440] I/http http close c122a70
[2026-05-15 15:37:41.553][000000010.441] I/user.Ethernet网卡httpdns域名解析成功
[2026-05-15 15:37:41.559][000000010.442] I/user.httpdns baidu.com 110.242.74.102
[2026-05-15 15:37:41.563][000000010.442] I/user.设置网卡 Ethernet
[2026-05-15 15:37:41.568][000000010.443] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5
[2026-05-15 15:37:41.573][000000010.443] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114
[2026-05-15 15:37:41.578][000000010.444] I/user.netdrv_multiple_notify_cbfunc use new adapter Ethernet 4
[2026-05-15 15:37:41.583][000000010.444] I/user.exnetif publish network status Ethernet 4
[2026-05-15 15:37:44.544][000000013.445] I/user.4G网卡开始PING
[2026-05-15 15:37:44.546][000000013.445] I/user.dns_request 4G true
[2026-05-15 15:37:44.809][000000013.710] I/http http close c122a70
[2026-05-15 15:37:44.812][000000013.712] I/user.4G网卡httpdns域名解析成功
[2026-05-15 15:37:44.817][000000013.713] I/user.httpdns baidu.com 111.63.65.103
[2026-05-15 15:37:45.540][000000014.434] I/user.sip_app_key 按下BOOT键
[2026-05-15 15:37:45.543][000000014.435] I/user.sip_app_key 呼入中，接听
[2026-05-15 15:37:45.547][000000014.436] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil
[2026-05-15 15:37:45.553][000000014.436] I/user.exsip answering call
[2026-05-15 15:37:45.557][000000014.437] I/user.sip_app_main_task_func after process STATE_INCOMING
[2026-05-15 15:37:45.563][000000014.437] I/user.sip cmd answer 
[2026-05-15 15:37:45.568][000000014.438] I/user.test ip 192.168.1.101
[2026-05-15 15:37:45.573][000000014.443] I/user.sip answer 200 OK
[2026-05-15 15:37:45.581][000000014.458] I/user.sip req ACK from 180.152.6.34 8910
[2026-05-15 15:37:45.586][000000014.459] I/user.JQsip media session ready table: 0C7BDF88
[2026-05-15 15:37:45.591][000000014.460] I/user.JQsip emit_event media ready function
[2026-05-15 15:37:45.597][000000014.460] I/user.exsip event: media action: ready
[2026-05-15 15:37:45.602][000000014.461] I/user.exsip media ready 180.152.6.34 15618 PCMU
[2026-05-15 15:37:45.607][000000014.461] I/user.exsip start voip engine with adapter: 4 remote: 180.152.6.34:15618
[2026-05-15 15:37:45.614][000000014.462] I/user.exsip voip engine started 180.152.6.34:15618 codec=PCMU adapter nil
[2026-05-15 15:37:45.618][000000014.463] I/user.sip_callback STATE_INCOMING media ready table: 0C7BDF88 nil
[2026-05-15 15:37:45.629][000000014.463] I/user.sip_callback 媒体通道就绪 180.152.6.34:15618
[2026-05-15 15:37:45.631][000000014.464] I/user.sip call established (incoming)
[2026-05-15 15:37:45.635][000000014.465] I/user.JQsip emit_event call established function
[2026-05-15 15:37:45.640][000000014.465] I/user.exsip event: call action: established
[2026-05-15 15:37:45.646][000000014.466] I/user.sip_callback STATE_INCOMING call connected table: 0C7BD718 nil
[2026-05-15 15:37:45.651][000000014.466] I/user.sip_callback call event sub_event= connected
[2026-05-15 15:37:45.655][000000014.466] I/user.sip_callback 通话已建立
[2026-05-15 15:37:45.661][000000014.467] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil
[2026-05-15 15:37:45.667][000000014.468] I/user.sip_app_main_task_func after process STATE_CONNECTED
[2026-05-15 15:37:45.672][000000014.468] I/user.sip_app_key 通话建立成功
[2026-05-15 15:37:45.677][000000014.469] D/voip voip task started
[2026-05-15 15:37:45.682][000000014.469] D/voip voip start event
[2026-05-15 15:37:45.687][000000014.470] E/voip voip config: remote=180.152.6.34:15618 codec=0 ptime=20
[2026-05-15 15:37:45.696][000000014.470] E/voip voio origin: samples=8000
[2026-05-15 15:37:45.702][000000014.470] E/voip voio frame: samples=160 bytes=320
[2026-05-15 15:37:45.707][000000014.476] I/voip aec ready frame=160 tail_ms=200 denoise=1
[2026-05-15 15:37:45.709][000000014.478] D/net adapter 4 connect 180.152.6.34:15618 UDP
[2026-05-15 15:37:45.714][000000014.478] E/voip udp socket created and connected to 180.152.6.34:15618
[2026-05-15 15:37:45.718][000000014.479] luat_i2s_save_old_config 279:i2s1 save old param
[2026-05-15 15:37:45.723][000000014.496] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-05-15 15:37:45.729][000000014.497] I/user.exsip voip state: started
[2026-05-15 15:37:45.733][000000014.497] I/user.sip_callback STATE_CONNECTED voip state started nil
[2026-05-15 15:37:45.738][000000014.498] I/user.sip_callback VoIP状态: started
[2026-05-15 15:37:45.744][000000014.498] I/voip voip running: 180.152.6.34:15618 codec=0 ptime=20
[2026-05-15 15:37:49.357][000000018.247] W/voip_jb jb resync: expected_seq 58447 -> 58445 (pending 1)
[2026-05-15 15:37:50.450][000000019.346] W/voip_jb jb resync: expected_seq 58500 -> 58498 (pending 1)
[2026-05-15 15:37:50.605][000000019.497] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7BCD60 nil
[2026-05-15 15:37:50.607][000000019.497] I/user.sip_callback VoIP统计 - 发送: 250 接收: 232 丢失: 0
[2026-05-15 15:37:51.914][000000020.806] W/voip_jb jb resync: expected_seq 58571 -> 58569 (pending 1)
[2026-05-15 15:37:54.465][000000023.366] W/voip_jb jb resync: expected_seq 58697 -> 58695 (pending 1)
[2026-05-15 15:37:55.041][000000023.939] I/user.sip req BYE from 180.152.6.34 8910
[2026-05-15 15:37:55.047][000000023.942] I/user.JQsip emit_event media stop function
[2026-05-15 15:37:55.052][000000023.943] I/user.exsip event: media action: stop
[2026-05-15 15:37:55.060][000000023.943] I/user.exsip voip engine stopping
[2026-05-15 15:37:55.065][000000023.944] I/user.sip_callback STATE_CONNECTED media stop table: 0C7BACB0 nil
[2026-05-15 15:37:55.070][000000023.944] I/user.sip_callback 媒体通道已关闭，关闭原因： peer_hangup
[2026-05-15 15:37:55.078][000000023.944] I/user.sip peer hung up
[2026-05-15 15:37:55.089][000000023.945] I/user.JQsip emit_event call ended function
[2026-05-15 15:37:55.093][000000023.945] I/user.exsip event: call action: ended
[2026-05-15 15:37:55.097][000000023.946] I/user.exsip voip engine stopping
[2026-05-15 15:37:55.102][000000023.946] I/user.sip_callback STATE_CONNECTED call ended table: 0C7BAC08 nil
[2026-05-15 15:37:55.108][000000023.946] I/user.sip_callback call event sub_event= ended
[2026-05-15 15:37:55.112][000000023.947] I/user.sip_callback 通话已结束，结束原因为： peer_hangup 通话对象： table: 0C7BFEF0
[2026-05-15 15:37:55.121][000000023.948] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED nil
[2026-05-15 15:37:55.127][000000023.948] I/user.sip_app_main_task_func after process STATE_READY
[2026-05-15 15:37:55.133][000000023.949] I/user.sip_app_key 通话已断开


```

接听通话结束，在本例中，还可以单击Air8000开发板的boot按键，进行拨号测试，单击POWERKEY挂断电话，日志如下：

```
[2026-05-15 15:25:29.788][000000378.211] I/user.sip_app_key 按下BOOT键
[2026-05-15 15:25:29.791][000000378.213] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100000
[2026-05-15 15:25:29.795][000000378.214] I/user.exsip calling: 100000
[2026-05-15 15:25:29.804][000000378.214] I/user.sip_app_main_task_func after process STATE_DIALING
[2026-05-15 15:25:29.810][000000378.215] I/user.sip cmd call 100000
[2026-05-15 15:25:29.815][000000378.217] I/user.test ip 192.168.1.101
[2026-05-15 15:25:29.821][000000378.219] I/user.sip setting call timeout 30 seconds
[2026-05-15 15:25:29.827][000000378.222] I/user.sip send INVITE sip:100000@180.152.6.34
[2026-05-15 15:25:29.832][000000378.237] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910
[2026-05-15 15:25:29.838][000000378.250] I/user.JQsip emit_event call auth_retry function
[2026-05-15 15:25:29.843][000000378.251] I/user.exsip event: call action: auth_retry
[2026-05-15 15:25:29.867][000000378.279] I/user.sip resp 100 Trying from 180.152.6.34 8910
[2026-05-15 15:25:30.006][000000378.424] I/user.sip resp 180 Ringing from 180.152.6.34 8910
[2026-05-15 15:25:30.013][000000378.426] I/user.sip invite provisional response 180 Ringing
[2026-05-15 15:25:30.018][000000378.427] I/user.JQsip emit_event call ringing function
[2026-05-15 15:25:30.023][000000378.427] I/user.exsip event: call action: ringing
[2026-05-15 15:25:30.029][000000378.427] I/user.sip_callback STATE_DIALING call ringing table: 0C7CAAC8 nil
[2026-05-15 15:25:30.034][000000378.428] I/user.sip_callback call event sub_event= ringing
[2026-05-15 15:25:30.040][000000378.428] I/user.sip_callback 对方响铃中
[2026-05-15 15:25:33.140][000000381.555] I/user.sip send OPTIONS ping
[2026-05-15 15:25:33.155][000000381.569] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-15 15:25:33.218][000000381.628] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-15 15:25:33.224][000000381.631] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1778813418 1778813419 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16516 RTP/AVP 0 101
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-15 15:25:33.240][000000381.633] I/user.sip stopping all call timers, clearing timeout_timer
[2026-05-15 15:25:33.255][000000381.637] I/user.JQsip media session ready table: 0C7A8718
[2026-05-15 15:25:33.267][000000381.638] I/user.JQsip emit_event media ready function
[2026-05-15 15:25:33.273][000000381.638] I/user.exsip event: media action: ready
[2026-05-15 15:25:33.279][000000381.639] I/user.exsip media ready 180.152.6.34 16516 PCMU
[2026-05-15 15:25:33.281][000000381.639] I/user.exsip start voip engine with adapter: 4 remote: 180.152.6.34:16516
[2026-05-15 15:25:33.289][000000381.640] I/user.exsip voip engine started 180.152.6.34:16516 codec=PCMU adapter nil
[2026-05-15 15:25:33.293][000000381.641] I/user.sip_callback STATE_DIALING media ready table: 0C7A8718 nil
[2026-05-15 15:25:33.299][000000381.641] I/user.sip_callback 媒体通道就绪 180.152.6.34:16516
[2026-05-15 15:25:33.305][000000381.642] I/user.sip call established (outgoing)
[2026-05-15 15:25:33.310][000000381.642] I/user.JQsip emit_event call established function
[2026-05-15 15:25:33.314][000000381.643] I/user.exsip event: call action: established
[2026-05-15 15:25:33.322][000000381.643] I/user.sip_callback STATE_DIALING call connected table: 0C7B0760 nil
[2026-05-15 15:25:33.327][000000381.643] I/user.sip_callback call event sub_event= connected
[2026-05-15 15:25:33.331][000000381.644] I/user.sip_callback 通话已建立
[2026-05-15 15:25:33.339][000000381.645] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil
[2026-05-15 15:25:33.345][000000381.645] I/user.sip_app_main_task_func after process STATE_CONNECTED
[2026-05-15 15:25:33.353][000000381.646] I/user.sip_app_key 通话建立成功
[2026-05-15 15:25:33.358][000000381.646] D/voip voip task started
[2026-05-15 15:25:33.366][000000381.647] D/voip voip start event
[2026-05-15 15:25:33.373][000000381.647] E/voip voip config: remote=180.152.6.34:16516 codec=0 ptime=20
[2026-05-15 15:25:33.379][000000381.648] E/voip voio origin: samples=8000
[2026-05-15 15:25:33.388][000000381.648] E/voip voio frame: samples=160 bytes=320
[2026-05-15 15:25:33.392][000000381.653] I/voip aec ready frame=160 tail_ms=200 denoise=1
[2026-05-15 15:25:33.397][000000381.655] D/net adapter 4 connect 180.152.6.34:16516 UDP
[2026-05-15 15:25:33.403][000000381.656] E/voip udp socket created and connected to 180.152.6.34:16516
[2026-05-15 15:25:33.407][000000381.656] luat_i2s_save_old_config 279:i2s1 save old param
[2026-05-15 15:25:33.412][000000381.673] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-05-15 15:25:33.419][000000381.673] I/user.exsip voip state: started
[2026-05-15 15:25:33.423][000000381.674] I/user.sip_callback STATE_CONNECTED voip state started nil
[2026-05-15 15:25:33.428][000000381.674] I/user.sip_callback VoIP状态: started
[2026-05-15 15:25:33.434][000000381.675] I/voip voip running: 180.152.6.34:16516 codec=0 ptime=20
[2026-05-15 15:25:37.715][000000386.124] W/voip_jb jb resync: expected_seq 26891 -> 26889 (pending 1)
[2026-05-15 15:25:38.258][000000386.673] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7AC908 nil
[2026-05-15 15:25:38.261][000000386.674] I/user.sip_callback VoIP统计 - 发送: 250 接收: 233 丢失: 0
[2026-05-15 15:25:39.050][000000387.464] W/voip_jb jb resync: expected_seq 26956 -> 26954 (pending 1)
[2026-05-15 15:25:41.721][000000390.144] W/voip_jb jb resync: expected_seq 27088 -> 27086 (pending 1)
[2026-05-15 15:25:42.827][000000391.245] W/voip_jb jb resync: expected_seq 27141 -> 27139 (pending 1)
[2026-05-15 15:25:43.262][000000391.673] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7B4C48 nil
[2026-05-15 15:25:43.265][000000391.674] I/user.sip_callback VoIP统计 - 发送: 500 接收: 477 丢失: 0
[2026-05-15 15:25:43.559][000000391.984] W/voip_jb jb resync: expected_seq 27176 -> 27174 (pending 1)
[2026-05-15 15:25:48.088][000000396.508] I/user.sip_app_key 按下POWERKEY键
[2026-05-15 15:25:48.092][000000396.509] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil
[2026-05-15 15:25:48.097][000000396.509] I/user.exsip hanging up
[2026-05-15 15:25:48.102][000000396.510] I/user.sip_app_main_task_func after process STATE_CONNECTED
[2026-05-15 15:25:48.106][000000396.511] I/user.sip cmd hangup 
[2026-05-15 15:25:48.111][000000396.511] I/user.sip BYE uri sip:100000@180.152.6.34:8910;transport=udp from <sip:100001@180.152.6.34>;tag=827c6d1924d5bb13 to <sip:100000@180.152.6.34>;tag=Stc12XD5BaS4m routes 0
[2026-05-15 15:25:48.116][000000396.514] I/user.sip send BYE
[2026-05-15 15:25:48.122][000000396.525] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-15 15:25:48.130][000000396.527] I/user.JQsip emit_event media stop function
[2026-05-15 15:25:48.132][000000396.528] I/user.exsip event: media action: stop
[2026-05-15 15:25:48.138][000000396.528] I/user.exsip voip engine stopping
[2026-05-15 15:25:48.143][000000396.529] I/user.sip_callback STATE_CONNECTED media stop table: 0C7BC4E0 nil
[2026-05-15 15:25:48.155][000000396.529] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup
[2026-05-15 15:25:48.159][000000396.529] I/user.sip call cleared
[2026-05-15 15:25:48.166][000000396.530] I/user.JQsip emit_event call ended function
[2026-05-15 15:25:48.173][000000396.530] I/user.exsip event: call action: ended
[2026-05-15 15:25:48.177][000000396.531] I/user.exsip voip engine stopping
[2026-05-15 15:25:48.186][000000396.531] I/user.sip_callback STATE_CONNECTED call ended table: 0C7BC6C8 nil
[2026-05-15 15:25:48.191][000000396.531] I/user.sip_callback call event sub_event= ended
[2026-05-15 15:25:48.202][000000396.532] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C79C768
[2026-05-15 15:25:48.209][000000396.533] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED nil
[2026-05-15 15:25:48.215][000000396.533] I/user.sip_app_main_task_func after process STATE_READY
[2026-05-15 15:25:48.220][000000396.534] I/user.sip_app_key 通话已断开


```