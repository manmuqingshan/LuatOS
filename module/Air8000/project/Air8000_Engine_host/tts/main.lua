
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "testtts"
VERSION = "2.0.0"

--[[
本demo当前仅支持ec618系列和ec718系列

## 提醒:
1. 本demo需要2022.12.21及之后的源码所编译的LuatOS固件
2. 本demo若使用外置TTS资源的LuatOS固件, 就必须有外挂的SPI Flash, 起码1M字节, 后面有刷写说明
3. 下载脚本时, 把txt也加上一起下载
4. 本demo需要音频扩展板, 780E只有I2S输出, 需要codec和PA才能驱动喇叭
5. 内置TTS资源的LuatOS最低版本是V1104,且去掉了很多库, 尤其是UI方面的库

## 使用本demo前,如果是外置TTS资源的LuatOS固件, 必须先刷tts.binpkg进行SPI Flash的刷写
1. 下载链接:
    618系列:https://gitee.com/openLuat/luatos-soc-2022/attach_files
    718系列:https://gitee.com/openLuat/luatos-soc-2023/attach_files
2. 在LuaTools主界面, 用"下载固件"按钮进行下载.
3. 下载前需要接好SPI Flash!!
4. 下载前选日志模式 4G USB, luatools版本号2.1.85或以上

## SPI Flash布局, 以1M字节为例,供参考:

-----------------------------------
64 k 保留空间, 用户自行分配
-----------------------------------
704k TTS数据
-----------------------------------
剩余空间, 256k,用户自行分配
-----------------------------------

## 基本流程:
1. 初始化sfud, 本demo使用SPI0 + GPIO8
2. 使用 audio.tts播放文本
3. 等待 播放结束事件
4. 从第二步重新下一个循环

## 接线说明

以780E开发板为例, 需要1.5版本或以上,团购版本均为1.5或以上.
1.4版本SPI分布有所不同, 注意区分.

https://wiki.luatos.com/chips/air780e/board.html

 xx脚指开发板pinout图上的顺序编号, 非GPIO编号

Flash -- 开发板
GND   -- 16脚, GND
VCC   -- 15脚, 3.3V
CLK   -- 14脚, GPIO11/SPI0_CLK/LCD_CLK, 时钟. 如果是1.4版本的开发板, 接05脚的GPIO11/UART2_TXD
MOSI  -- 13脚, GPIO09/SPI0_MOSI/LCD_OUT,主控数据输出
MISO  -- 11脚, GPIO10/SPI0_MISO/LCD_RS,主控数据输入. 如果是1.4版本的开发板, 接06脚的GPIO10/UART2_RXD
CS    -- 10脚, GPIO08/SPI0_CS/LCD_CS,片选.

注意: 12脚是跳过的, 接线完毕后请检查好再通电!!
]]

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域

local i2c_id = 0            -- i2c_id 0

local pa_pin = 16           -- 喇叭pa功放脚
local power_pin = 2         -- es8311电源脚

local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_bits_per_sample = 16  -- 数据位数
local i2s_channel_format = i2s.MONO_R   -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量

local multimedia_id = 0         -- 音频通道 0
local pa_on_level = 1           -- PA打开电平 1 高电平 0 低电平
local power_delay = 3           -- 在DAC启动前插入的冗余时间，单位100ms
local pa_delay = 100            -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_on_level = 1        -- 电源控制IO的电平，默认拉高
local power_time_delay = 100    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 70        -- 喇叭音量
local mic_vol = 80          -- 麦克风音量

function audio_setup()
    pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(100)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电

    i2c.setup(i2c_id,i2c.FAST)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    sys.publish("AUDIO_READY")
end

-- 配置好audio外设
sys.taskInit(audio_setup)

local taskName = "task_audio"

local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

audio.on(0, function(id, event)
    --使用play来播放文件时只有播放完成回调
    local succ,stop,file_cnt = audio.getError(0)
    if not succ then
        if stop then
            log.info("用户停止播放")
        else
            log.info("第", file_cnt, "个文件解码失败")
        end
    end
    sysplus.sendMsg(taskName, MSG_PD)
end)


local function audio_task()
    local result    
    sys.waitUntil("AUDIO_READY")

    -- 本例子是按行播放 "千字文", 文本来源自wiki百科
    local fd = nil
    local line = nil
    while true do
        log.info("开始播放")
        line = nil
        if not fd then
            fd = io.open("/luadb/qianzw.txt")
        end
        if fd then
            line = fd:read("*l")
            if line == nil then
                fd:close()
                fd = nil
            end
        end
        if line == nil then
            line = "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十"
        end
        line = line:trim()
        log.info("播放内容", line)
        result = audio.tts(0, line)
        if result then
        --等待音频通道的回调消息，或者切换歌曲的消息
            while true do
                msg = sysplus.waitMsg(taskName, nil)
                if type(msg) == 'table' then
                    if msg[1] == MSG_PD then
                        log.info("播放结束")
                        break
                    end
                else
                    log.error(type(msg), msg)
                end
            end
        else
            log.debug("解码失败!")
            sys.wait(1000)
        end
        if not audio.isEnd(0) then
            log.info("手动关闭")
            audio.playStop(0)
        end
        if audio.pm then
		    audio.pm(0,audio.STANDBY)
        end
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        log.info("mem", "sys", rtos.meminfo("sys"))
        log.info("mem", "lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
    sysplus.taskDel(taskName)
end

sysplus.taskInitEx(audio_task, taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
