--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 001.000.000
@date    2025.08.25
@author  王棚嶙
@usage
本 Demo 完整覆盖了 TF 卡操作的核心到高级流程，HTTP下载功能包括：
1. 基础操作：
   - CH390 供电控制
   - 看门狗守护机制 
2. 挂载及文件操作：
   - 文件系统挂载/卸载
   - TF卡空间信息查询
   - 文件创建/读写/追加
   - 目录创建/删除
   - 文件重命名/删除
   - 文件存在性检查与大小获取
3. 下载功能：
   - 网络检测与HTTP文件下载
更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
        
PROJECT = "tfcard"
VERSION = "001.000.000"




-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)



--加载ch390控制模块，仅限于AIR8000整机开发板系列
require "ch390_manager"

--[[在加载以下三个功能时，建议分别打开进行测试，因为文件操作，http下载功能和http大文件上传功能是异步操作。
放到一个项目中，如果加载的时间点是随机的，就会出现tfcard_app在spi.setup和fatfs挂载文件系统之后，
还没有释放资源，然后http_download_file或http_upload_file又去重复spi.setup和fatfs挂载文件系统了，
不符合正常的业务逻辑，用户在参考编程的时候也要注意。]]

--加载tf卡测试应用模块
-- require "tfcard_app"
--加载HTTP下载存入TF卡功能演示模块
--require "http_download_file"
--加载HTTP上传文件到服务器的功能演示模块
require "http_upload_file"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!