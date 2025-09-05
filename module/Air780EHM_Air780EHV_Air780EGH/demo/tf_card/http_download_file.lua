--[[
@module http_download_file
@summary http下载文件模块
@version 1.0.0
@date    2025.08.25
@author  王棚嶙
@usage
本文件演示的功能为通过http下载文件进入TF卡中：
1. 网络就绪检测
2. 创建HTTP下载任务并等待完成
3. 记录下载结果
4. 获取并记录文件大小
本文件没有对外接口，直接在main.lua中require "http_download_file"即可
]] 


local function http_download_file_task()

    -- 阶段1: 网络就绪检测

    while not socket.adapter(socket.dft()) do
        log.warn("HTTP下载", "等待网络连接", socket.dft())
        -- 等待IP_READY消息，超时设为1秒
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("HTTP下载", "网络已就绪", socket.dft())

    -- 如果使用核心板演示环境，请打开33——36行代码，同时关闭38——43行的代码。
    -- 如果使用开发板演示环境，请打开38——43行代码，同时关闭33——36行的代码。
    -- 在Air780EHM/EHV/EGH核心板上TF卡的的pin_cs为gpio8，spi_id为0.请根据实际硬件修改
    spi_id, pin_cs = 0, 8
    spi.setup(spi_id, nil, 0, 0, 400 * 1000)
    -- 初始化后拉高pin_cs,准备开始挂载TF卡
    gpio.setup(pin_cs, 1)

    -- Air780EHM/EHV/EGH开发板上的pin_cs为gpio16，spi_id为0.请根据实际硬件修改
    -- spi_id, pin_cs = 0, 16
    -- spi.setup(spi_id, nil, 0, 0, 400 * 1000)
    -- 设置片选引脚同一spi总线上的所有从设备在初始化时必须要先拉高CS脚，防止从设备之间互相干扰。
    -- 在Air780EHM/EHV/EGH开发板上，TF卡和ch390共用SPI0总线。
    -- gpio.setup(pin_cs, 1)

    -- 挂载文件系统
    local mount_ok = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    if not mount_ok then
        log.error("HTTP下载", "文件系统挂载失败")
        fatfs.unmount("/sd")
        spi.close(spi_id)
        return
    end

    -- 阶段2: 执行下载任务
    log.info("HTTP下载", "开始下载任务")

    -- 核心下载操作开始 (支持http和https)
    -- local code, headers, body = http.request("GET", "...", nil, nil, {dst = "/sd/1.mp3"}).wait()
    -- 其中 "..."为url地址, 支持 http和https, 支持域名, 支持自定义端口。
    local code, headers, body_size = http.request("GET",
                                    "https://gitee.com/openLuat/LuatOS/raw/master/module/Air780EHM_Air780EHV_Air780EGH/demo/audio/1.mp3",
                                    nil, nil, {dst = "/sd/1.mp3"}).wait()
    -- 阶段3: 记录下载结果
    log.info("HTTP下载", "下载完成", 
        code==200 and "success" or "error", 
        code, 
        -- headers是下载的文件头信息
        json.encode(headers or {}), 
        -- body_size是下载的文件大小（字节数）
        body_size) 
        
    if code == 200 then
        -- 获取实际文件大小
        local actual_size = io.fileSize("/sd/1.mp3")
        log.info("HTTP下载", "文件大小验证", "预期:", body_size, "实际:", actual_size)
        
        if actual_size~= body_size then
            log.error("HTTP下载", "文件大小不一致", "预期:", body_size, "实际:", actual_size)
        end
    end

    -- 阶段4: 资源清理
    fatfs.unmount("/sd")
    spi.close(spi_id)
    log.info("HTTP下载", "资源清理完成")
end

-- 创建下载任务
sys.taskInit(http_download_file_task)
