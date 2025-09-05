-- talk.lua
local talk = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

local run_state = false
local airaudio  = require "airaudio"
local input_method = require "InputMethod" 
local input_key = false

-- 初始化fskv
AIRTALK_TASK_NAME = "airtalk_task"
USER_TASK_NAME = "user"

MSG_CONNECT_ON_IND = 0
MSG_CONNECT_OFF_IND = 1
MSG_AUTH_IND = 2
MSG_SPEECH_ON_IND = 3
MSG_SPEECH_OFF_IND = 4
MSG_SPEECH_CONNECT_TO = 5

MSG_PERSON_SPEECH_TEST_START = 20
MSG_GROUP_SPEECH_TEST_START = 21
MSG_SPEECH_STOP_TEST_END = 22


MSG_READY = 10
MSG_NOT_READY = 11
MSG_TYPE = 12

-- 新增消息类型
MSG_ADDRESS_LIST_OPEN = 30
MSG_ADDRESS_LIST_BACK = 31
MSG_ADDRESS_LIST_PREV = 32
MSG_ADDRESS_LIST_NEXT = 33
MSG_ADDRESS_LIST_SELECT = 34


SP_T_NO_READY = 0           -- 离线状态无法对讲
SP_T_IDLE = 1               -- 对讲空闲状态
SP_T_CONNECTING = 2         -- 主动发起对讲
SP_T_CONNECTED = 3          -- 对讲中


SUCC = "success"
local speech_topic = nil
local mqtt_host = "lbsmqtt.openluat.com"
local mqtt_port = 1886
local mqtt_isssl = false
local client_id = nil
local user_name = "mqtt_hz_test_1"
local password = "Ck8WpNCp"
local mqttc = nil
local message = ""
local event = ""
local talk_state = ""
local mqttc = nil
local g_state = SP_T_NO_READY   --device状态
local g_mqttc = nil             --mqtt客户端
local g_local_id                  --本机ID
local g_remote_id                 --对端ID
local g_s_type                  --对讲的模式，字符串形式的
local g_s_topic                 --对讲用的topic
local g_s_mode                  --对讲的模式
local g_dev_list = {}           --对讲列表

-- 新增通讯录相关变量
local address_list_page = 1     -- 通讯录当前页码
local address_list_max_page = 1 -- 通讯录最大页码
local current_page = "main"     -- 当前页面状态
local contacts_per_page = 8     -- 每页显示的联系人数量

local function auth()
    if g_state == SP_T_NO_READY then
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0001", json.encode({["key"] = PRODUCT_KEY, ["device_type"] = 1}))
    end
end

local function heart()
    -- if g_state == SP_T_CONNECTED then
        log.info("心跳上报")
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0005", json.encode({["csq"] = mobile.csq(), ["battery"] = 100}))
    -- end
end


--对讲开始，topic,ssrc,采样率(8K或者16K)这3个参数都有了之后就能进行对讲了，可以通过其他协议传入
local function speech_on(ssrc, sample)
    g_state = SP_T_CONNECTED
    g_mqttc:subscribe(g_s_topic)
    airtalk.set_topic(g_s_topic)
    airtalk.set_ssrc(ssrc)
    log.info("对讲模式", g_s_mode)
    airtalk.speech(true, g_s_mode, sample)
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, true) 
    
    sys.timerStopAll(wait_speech_to)
    log.info("对讲接通，可以说话了")
end
--对讲结束
local function speech_off(need_upload, need_ind)
    if g_state ==  SP_T_CONNECTED then
        g_mqttc:unsubscribe(g_s_topic)
        airtalk.speech(false)
        g_s_topic = nil
    end
    g_state = SP_T_IDLE
    sys.timerStopAll(auth)
    sys.timerStopAll(heart)
    sys.timerStopAll(wait_speech_to)
    log.info("对讲断开了")
    if need_upload then
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0004", json.encode({["to"] = g_remote_id}))
    end
    if need_ind then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_OFF_IND, true)
    end
end

function wait_speech_to()
    log.info("主动请求对讲超时无应答")
    speech_off(true, false)
end

local function analyze_v1(cmd, topic, obj)
    if cmd == "8005" or cmd == "8004" then       -- 对讲心跳保持和结束对讲的应答不做处理
        return
    end
    if cmd == "8003" then       -- 请求对讲应答
        if g_state ~= SP_T_CONNECTING then  --没有发起对讲请求
            log.error("state", g_state, "need", SP_T_CONNECTING)
            return
        else
            if obj and obj["result"] == SUCC and g_s_topic == obj["topic"]then  --完全正确，开始对讲
                speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                return
            else
                log.info(obj["result"], obj["topic"], g_s_topic)
                sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, false)   --有异常，无法对讲
            end
            
        end
        g_s_topic = nil
        g_state = SP_T_IDLE
        return
    end
    local new_obj = nil
    if cmd == "0102" then       -- 对端打过来
        if obj and obj["topic"] and obj["ssrc"] and obj["audio_code"] and obj["type"] then
            if g_state ~= SP_T_IDLE then    -- 空闲状态下才可以进入对讲状态
                log.error("state", g_state, "need", SP_T_IDLE)
                new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "device is busy"}
            else
                if obj["type"] == "one-on-one" then -- 1对1对讲
                    local from = string.match(obj["topic"], "audio/.*/(.*)/.*")
                    if from then
                        log.info("remote id ", from)
                        g_s_topic = obj["topic"]
                        g_remote_id = from
                        new_obj = {["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = ""}
                        g_s_type = "one-on-one"
                        g_s_mode = airtalk.MODE_PERSON
                        speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                    else
                        new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "topic error"}
                    end
                elseif obj["type"] == "broadcast" then  -- 1对多对讲
                    g_s_topic = obj["topic"]
                    new_obj = {["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = ""}
                    g_s_mode = airtalk.MODE_GROUP_LISTENER
                    g_s_type = "broadcast"
                    speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                end
            end
        else
            new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "json info error"}
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8102", json.encode(new_obj))
        return
    end

    if cmd == "0103" then   --对端挂断
        if g_state == SP_T_IDLE then
            new_obj = {["result"] = "failed", ["info"] = "no speech"}
        else
            if obj and obj["type"] == g_s_type then
                new_obj = {["result"] = SUCC, ["info"] = ""}
                speech_off(false, true)
            else
                new_obj = {["result"] = "failed", ["info"] = "type mismatch"}
            end
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8103", json.encode(new_obj))
        return
    end

    if cmd == "0101" then                        --更新设备列表
        if obj then
            g_dev_list = obj["dev_list"]
            -- 计算通讯录最大页码
            address_list_max_page = math.ceil(#g_dev_list / contacts_per_page)
            if address_list_max_page == 0 then
                address_list_max_page = 1
            end
            -- for i=1,#g_dev_list do
            --     log.info(g_dev_list[i]["id"],g_dev_list[i]["name"])
            -- end
            new_obj = {["result"] = SUCC, ["info"] = ""}
        else
            new_obj = {["result"] = "failed", ["info"] = "json info error"}
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8101", json.encode(new_obj))
        return
    end
    if cmd == "8001" then
        if obj and obj["result"] == SUCC then
            g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0002","")  -- 更新列表
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "鉴权失败" .. obj["info"]) 
        end
        return
    end
    if cmd == "8002" then
        if obj and obj["result"] == SUCC then   --收到设备列表更新应答，才能认为相关网络服务准备好了
            g_dev_list = obj["dev_list"]
            -- 计算通讯录最大页码
            address_list_max_page = math.ceil(#g_dev_list / contacts_per_page)
            if address_list_max_page == 0 then
                address_list_max_page = 1
            end
            for i=1,#g_dev_list do
                log.info(g_dev_list[i]["id"],g_dev_list[i]["name"])
            end
            g_state = SP_T_IDLE
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, true)  --完整登录流程结束
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "更新设备列表失败") 
        end
        return
    end
end

local function mqtt_cb(mqttc, event, topic, payload)
    log.info(event, topic)
    local msg,data,obj
    if event == "conack" then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_CONNECT_ON_IND) --mqtt连上了，开始自定义的鉴权流程
        g_mqttc:subscribe("ctrl/downlink/" .. g_local_id .. "/#")--单主题订阅
    elseif event == "suback" then
        if g_state == SP_T_NO_READY then
            if topic then
                auth()
            else
                sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "订阅失败" .. "ctrl/downlink/" .. g_local_id .. "/#") 
            end
        elseif g_state == SP_T_CONNECTED then
            if not topic then
                speech_off(false, true)
            end
        end
    elseif event == "recv" then
        local result = string.match(topic, g_dl_topic)
        if result then 
            local obj,res,err = json.decode(payload)
            analyze_v1(result, topic, obj)
        end
        result = nil
        data = nil
        obj = nil
        
    elseif event == "sent" then
        -- log.info("mqtt", "sent", "pkgid", data)
    elseif event == "disconnect" then
        speech_off(false, true)
        g_state = SP_T_NO_READY
    elseif event == "error" then

    end
end

local function task_cb(msg)
    if msg[1] == MSG_SPEECH_CONNECT_TO then
        speech_off(true,false)
    else
        log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
    end
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
    if event == airtalk.EVENT_ERROR then
        if param == airtalk.ERROR_NO_DATA then
            log.error("长时间没有收到音频数据")
            speech_off(true, true)
        end
    end
end

local function airtalk_mqtt_task()
    local msg,data,obj,online,num,res
    --g_local_id也可以自己设置
    
    g_dl_topic = "ctrl/downlink/" .. g_local_id .. "/(%w%w%w%w)"
    sys.timerLoopStart(next_auth, 900000)

    g_mqttc = mqtt.create(nil, "mqtt.airtalk.luatos.com", 1883, false, {rxSize = 32768})
    airtalk.config(airtalk.PROTOCOL_MQTT, g_mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    g_mqttc:auth(g_local_id,g_local_id,mobile.muid()) -- g_local_id必填,其余选填
    g_mqttc:keepalive(240) -- 默认值240s
    g_mqttc:autoreconn(true, 15000) -- 自动重连机制
    g_mqttc:debug(false)
    g_mqttc:on(mqtt_cb)
    log.info("设备信息", g_local_id, mobile.muid())
    -- mqttc自动处理重连, 除非自行关闭
    g_mqttc:connect()
    online = false
    while true do
        msg = sys.waitMsg(AIRTALK_TASK_NAME, MSG_CONNECT_ON_IND)   --等服务器连上
        log.info("connected")
        while not online do
            msg = sys.waitMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, 30000)   --登录流程不应该超过30秒
            if type(msg) == 'table' then
                online = msg[2]
                if online then
                    sys.timerLoopStart(auth, 3600000) --鉴权通过则60分钟后尝试重新鉴权
                else
                    log.info(msg[3])
                    sys.timerLoopStart(auth, 300000)       --5分钟后重新鉴权
                end
            else
                auth()  --30秒鉴权无效后重新鉴权
            end
        end
        log.info("对讲管理平台已连接")
        while online do
            msg = sys.waitMsg(AIRTALK_TASK_NAME)
            if type(msg) == 'table' and type(msg[1]) == "number" then
                if msg[1] == MSG_PERSON_SPEECH_TEST_START then
                    if g_state ~= SP_T_IDLE then
                        log.info("正在对讲无法开始")
                    else
                        log.info("匹配输入的设备号是在设备列表中")

                        res = false
                        for i=1,#g_dev_list do
                            res = string.match(g_dev_list[i]["id"], "(%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w)")
                            if res and res == speech_topic then
                                res = true          
                                break
                            end
                        end
                        if res then
                            log.info("向", speech_topic, "主动发起对讲")
                            g_state = SP_T_CONNECTING
                            g_remote_id = speech_topic
                            g_s_mode = airtalk.MODE_PERSON
                            g_s_type = "one-on-one"
                            g_s_topic = "audio/" .. g_local_id .. "/" .. g_remote_id .. "/" .. (string.sub(tostring(mcu.ticks()), -4, -1))
                            g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0003", json.encode({["topic"] = g_s_topic, ["type"] = g_s_type}))
                            sys.timerStart(wait_speech_to, 15000)
                        else
                            log.info("找不到有效的设备ID")
                        end
                    end
                elseif msg[1] == MSG_GROUP_SPEECH_TEST_START then
                    if g_state ~= SP_T_IDLE then
                        log.info("正在对讲无法开始")
                    else
                        log.info("测试一下1对多对讲功能")
                        g_remote_id = "all"
                        g_state = SP_T_CONNECTING
                        g_s_mode = airtalk.MODE_GROUP_SPEAKER
                        g_s_type = "broadcast"
                        g_s_topic = "audio/" .. g_local_id .. "/all/" .. (string.sub(tostring(mcu.ticks()), -4, -1))
                        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0003", json.encode({["topic"] = g_s_topic, ["type"] = g_s_type}))
                        sys.timerStart(wait_speech_to, 15000)
                    end
                elseif msg[1] == MSG_SPEECH_STOP_TEST_END then
                    if g_state ~= SP_T_CONNECTING and g_state ~= SP_T_CONNECTED then
                        log.info("没有对讲", g_state)
                    else
                        log.info("主动断开对讲")
                        speech_off(true, false)
                    end
                elseif msg[1] == MSG_SPEECH_ON_IND then
                    if msg[2] then
                        log.info("对讲接通")
                    else
                        log.info("对讲断开")
                    end
                elseif msg[1] == MSG_CONNECT_OFF_IND then
                    log.info("connect", msg[2])
                    online = msg[2]
                end
                obj = nil
            else
                log.info(type(msg), type(msg[1]))
            end
            msg = nil
        end
        online = false
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end


local function airtalk_event_cb(event, param)
    log.info("talk event", event, param)
    event  = event
end


-- MQTT回调函数
local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
    -- 连接成功时订阅主题
end

local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
    if msg[1] == MSG_SPEECH_IND then

    elseif msg[1] == MSG_NOT_READY then
        test_ready = false
        msg = sys.waitMsg(USER_TASK_NAME, MSG_TYPE)
    end
end
local function init_talk()
    log.info("init_call")
    airaudio.init() 
    airtalk_mqtt_init()
    sys.timerLoopStart(heart, 10000)
    local msg
    while true do
        msg = sys.waitMsg(USER_TASK_NAME, MSG_TYPE)
        if msg[2] then  -- true powerkey false boot key
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_GROUP_SPEECH_TEST_START)   
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_PERSON_SPEECH_TEST_START)   
        end 
        msg = sys.waitMsg(USER_TASK_NAME, MSG_TYPE)
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_STOP_TEST_END)        
    end

end



-- 输入法回调函数
local function submit_callback(input_text)
    if input_text and #input_text > 0 then
        speech_topic = input_text
        fskv.set("talk_number", input_text)  -- 保存对讲号码到fskv
        log.info("talk", "对讲号码:", fskv.get("talk_number"))
        input_key = false

    end
end

-- 绘制通讯录页面
local function draw_address_list()
    lcd.clear(_G.bkcolor)
    
    -- 绘制返回按钮 (左上角)
    lcd.showImage(10, 10, "/luadb/back.jpg")
    
    -- 绘制标题 (居中)
    lcd.drawStr(120, 30, "通讯录")
    
    -- 计算当前页的联系人起始和结束索引
    local start_index = (address_list_page - 1) * contacts_per_page + 1
    local end_index = math.min(start_index + contacts_per_page - 1, #g_dev_list)
    
    -- 绘制联系人列表
    local y_pos = 78
    for i = start_index, end_index do
        local contact = g_dev_list[i]
        
        -- 绘制ID
        lcd.drawStr(10, y_pos, "ID: " .. (contact["id"] or ""))
        
        -- 绘制名称
        lcd.drawStr(10, y_pos + 15, "名称: " .. (contact["name"] or "未知"))
        
        -- 绘制分隔线
        lcd.drawLine(5, y_pos + 35-12, 315, y_pos + 35-12)
        
        y_pos = y_pos + 40  -- 每个联系人占40像素高度
    end
    
    -- 绘制翻页按钮 (底部居中)
    local page_btn_y = 412
    if address_list_page > 1 then
        lcd.drawStr(50, page_btn_y, "上一页")
    end
    
    if address_list_page < address_list_max_page then
        lcd.drawStr(220, page_btn_y, "下一页")
    end
    
    -- 绘制页码信息 (底部居中)
    lcd.drawStr(140, page_btn_y, address_list_page .. "/" .. address_list_max_page)
    
    -- 如果正在通话，绘制停止按钮 (底部居中)
    if g_state == SP_T_CONNECTED then
        lcd.fill(120, 435, 200, 465,0xF061)  -- 绘制停止按钮边框
        lcd.drawStr(130, 462, "停止通话")
    end
    
    lcd.flush()
end

function talk.run()
    log.info("talk.run",airtalk.PROTOCOL_DEMO_MQTT_16K)
    lcd.setFont(lcd.font_opposansm12_chinese)
    
    run_state = true
    g_local_id = mobile.imei()
    sys.taskInitEx(init_talk, USER_TASK_NAME, task_cb)
    speech_topic = fskv.get("talk_number")
    log.info("get  speech_topic",speech_topic)

    while run_state do
        sys.wait(100)
        if input_method.is_active() then
            input_method.periodic_refresh()
        else
            if current_page == "main" then
                lcd.clear(_G.bkcolor) 
                if  speech_topic  == nil then
                    lcd.drawStr(0, 80, "输入任意手机号,并保证所有终端/平台一致")
                    lcd.drawStr(0, 100, "方案介绍:airtalk.luatos.com")
                    lcd.drawStr(0, 120, "平台端网址:airtalk.openluat.com/talk/")
                    lcd.drawStr(0, 140, "本机ID:" .. g_local_id)
                    lcd.showImage(32, 250, "/luadb/input_topic.jpg")
                    lcd.showImage(32, 350, "/luadb/broadcast.jpg")
                    lcd.showImage(104, 400, "/luadb/stop.jpg")
                    
                else
                    lcd.drawStr(0, 80, "对讲测试,测试topic:"..speech_topic )
                    lcd.drawStr(0, 100, "方案介绍:airtalk.luatos.com")
                    lcd.drawStr(0, 120, "平台端网址:airtalk.openluat.com/talk/")
                    lcd.drawStr(0, 140, "所有终端或者网页都要使用同一个topic")
                    lcd.drawStr(0, 160, talk_state)
                    lcd.drawStr(0, 180, "事件:" .. event)
                    lcd.drawStr(0, 200, "本机ID:" .. g_local_id)
                    -- 显示输入法入口按钮
                    lcd.showImage(32, 250, "/luadb/input_topic.jpg")
                    lcd.showImage(175, 300, "/luadb/datacall.jpg")
                    lcd.showImage(32, 300, "/luadb/broadcast.jpg")
                    lcd.showImage(104, 400, "/luadb/stop.jpg")
                    lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
                end
                
                -- 显示通讯录按钮 (位置x10,y250)
                lcd.showImage(175, 250, "/luadb/addresslist.jpg")
                
                lcd.showImage(0,0,"/luadb/back.jpg")
                lcd.flush()
            elseif current_page == "address_list" then
                draw_address_list()
            end
        end

        if not run_state then
            return true
        end
    end
end


local function stop_talk()
    talk_state = "停止对讲"
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_STOP_TEST_END)  -- 停止对讲
end


local function start_talk()
    talk_state = "一对一通话开始"
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_PERSON_SPEECH_TEST_START)  --  开始一对一流量电话
end

local function start_broadcast()
    talk_state = "语音采集上传中,正在广播"
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_GROUP_SPEECH_TEST_START)     --   开始广播
end


local function start_input()
    input_key = true
    input_method.init(false, "talk", submit_callback)  -- 直接传递函数
end

-- 打开通讯录
local function open_address_list()
    current_page = "address_list"
    address_list_page = 1
end

-- 返回主页面
local function back_to_main()
    current_page = "main"
end

-- 选择联系人
local function select_contact(index)
    local contact_index = (address_list_page - 1) * contacts_per_page + index
    if contact_index <= #g_dev_list then
        local contact = g_dev_list[contact_index]
        if contact and contact["id"] then
            speech_topic = contact["id"]
            fskv.set("talk_number", speech_topic)
            start_talk()
            -- 保持在通讯录页面，但显示停止按钮
        end
    end
end

-- 处理通讯录页面的触摸事件
local function handle_address_list_touch(x, y)
    -- 返回按钮区域 (左上角)
    if x > 10 and x < 50 and y > 10 and y < 50 then
        back_to_main()
        return
    end
    
    -- 上一页按钮区域 (底部左侧)
    if address_list_page > 1 and x > 40 and x < 90 and y > 390 and y < 420 then
        address_list_page = address_list_page - 1
        return
    end
    
    -- 下一页按钮区域 (底部右侧)
    if address_list_page < address_list_max_page and x > 210 and x < 260 and y > 390 and y < 420 then
        address_list_page = address_list_page + 1
        return
    end
    
    -- 停止通话按钮区域 (底部居中)
    if g_state == SP_T_CONNECTED and x > 120 and x < 200 and y > 435 and y < 465 then
        stop_talk()
        return
    end
    
    -- 联系人选择区域 (60-380像素高度)
    if y >= 60 and y <= 380 then
        local contact_index = math.floor((y - 60) / 40) + 1
        if contact_index >= 1 and contact_index <= contacts_per_page then
            select_contact(contact_index)
        end
    end
end

function talk.tp_handal(x, y, event)
    if input_key then
        input_method.process_touch(x, y)
    else
        if current_page == "main" then
            if x > 0 and x < 80 and y > 0 and y < 80 then
                run_state = false 
            elseif x > 32 and x < 133 and y > 250 and y < 295 then
                sysplus.taskInitEx(start_input,"start_input")
            elseif x > 173 and x < 284 and y > 300 and y < 345 then
                sysplus.taskInitEx(start_talk, "start_talk")
            elseif x > 32 and x < 133 and y > 300 and y < 345 then
                sysplus.taskInitEx(start_broadcast, "start_broadcast")
            elseif x > 104 and x < 215 and y > 397 and y < 444 then
                sysplus.taskInitEx(stop_talk, "stop_talk")
            elseif x > 175 and x < 286 and y > 250 and y < 295 then  -- 通讯录按钮
                sysplus.taskInitEx(open_address_list, "open_address_list")
            end
        elseif current_page == "address_list" then
            handle_address_list_touch(x, y)
        end
    end
end

return talk