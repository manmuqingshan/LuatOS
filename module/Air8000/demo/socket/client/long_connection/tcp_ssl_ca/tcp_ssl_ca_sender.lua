--[[
@module  tcp_ssl_ca_sender
@summary tcp_ssl_ca client socket数据发送应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为tcp_ssl_ca client socket数据发送应用功能模块，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、tcp_ssl_ca_main主任务调用tcp_ssl_ca_sender.proc接口，遍历队列send_queue，逐条发送数据到server；
3、tcp_ssl_ca client socket和server之间的连接如果出现异常，tcp_ssl_ca_main主任务调用tcp_ssl_ca_sender.exception_proc接口，丢弃掉队列send_queue中未发送的数据；
4、任何一条数据无论发送成功还是失败，只要这条数据有回调函数，都会通过回调函数通知数据发送方；

本文件的对外接口有3个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
   其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
   本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
2、tcp_ssl_ca_sender.proc：数据发送应用逻辑处理入口，在tcp_ssl_ca_main.lua中调用；
3、tcp_ssl_ca_sender.exception_proc：数据发送应用逻辑异常处理入口，在tcp_ssl_ca_main.lua中调用；
]]

local tcp_ssl_ca_sender = {}

local libnet = require "libnet"

--[[
数据发送队列，数据结构为：
{
    [1] = {data="data1", cb={func=callback_function1, para=callback_para1}},
    [2] = {data="data2", cb={func=callback_function2, para=callback_para2}},
}
data的内容为真正要发送的数据，必须存在；
func的内容为数据发送结果的用户回调函数，可以不存在
para的内容为数据发送结果的用户回调函数的回调参数，可以不存在；
]]
local send_queue = {}

-- tcp_ssl_ca_main的任务名
tcp_ssl_ca_sender.TASK_NAME = "tcp_ssl_ca_main"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, data, cb)
    -- 将原始数据增加前缀，然后插入到发送队列send_queue中
    table.insert(send_queue, {data="send from "..tag..": "..data, cb=cb})
    -- 通知tcp_ssl_ca_main主任务有数据需要发送
    -- tcp_ssl_ca_main主任务如果处在libnet.wait调用的阻塞等待状态，就会退出阻塞状态
    sys.sendMsg(tcp_ssl_ca_sender.TASK_NAME, socket.EVENT, 0)
end

--[[
检查socket client是否需要发送数据，如果需要发送数据，读取并且发送完发送队列中的所有数据

@api tcp_ssl_ca_sender.proc(task_name, socket_client)

@param1 task_name string
表示socket.create接口创建socket client对象时所处的task的name；
必须传入，不允许为空或者nil；

@param2 socket_client userdata
表示由socket.create接口创建的socket client对象；
必须传入，不允许为空或者nil；

@return1 result bool
表示处理结果，成功为true，失败为false

@usage
tcp_ssl_ca_sender.proc("tcp_client_main", socket_client)
]]
function tcp_ssl_ca_sender.proc(task_name, socket_client)
    local send_item
    local result, buff_full

    -- 遍历数据发送队列send_queue
    while #send_queue>0 do
        -- 取出来第一条数据赋值给send_item
        -- 同时从队列send_queue中删除这一条数据
        send_item = table.remove(send_queue,1)

        -- 发送这条数据，超时时间15秒钟
        result, buff_full = libnet.tx(task_name, 15000, socket_client, send_item.data)

        -- 发送失败
        if not result then
            log.error("tcp_ssl_ca_sender.proc", "libnet.tx error")

            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if send_item.cb and send_item.cb.func then
                send_item.cb.func(false, send_item.cb.para)
            end

            return false
        end

        -- 如果内核固件中缓冲区满了，则将send_item再次插入到send_queue的队首位置，等待下次尝试发送
        if buff_full then
            log.error("tcp_ssl_ca_sender.proc", "buffer is full, wait for the next time")
            table.insert(send_queue, 1, send_item)
            return true
        end

        log.info("tcp_ssl_ca_sender.proc", "send success")
        -- 发送成功，如果当前发送的数据有用户回调函数，则执行用户回调函数
        if send_item.cb and send_item.cb.func then
            send_item.cb.func(true, send_item.cb.para)
        end

        -- 发送成功，通知网络环境检测看门狗功能模块进行喂狗
        sys.publish("FEED_NETWORK_WATCHDOG")
    end

    return true
end

--[[
socket client连接出现异常时，清空等待发送的数据，并且执行发送方的回调函数

@api tcp_ssl_ca_sender.exception_proc()

@usage
tcp_ssl_ca_sender.exception_proc()
]]
function tcp_ssl_ca_sender.exception_proc()
    -- 遍历数据发送队列send_queue
    while #send_queue>0 do
        local send_item = table.remove(send_queue,1)
        -- 发送失败，如果当前发送的数据有用户回调函数，则执行用户回调函数
        if send_item.cb and send_item.cb.func then
            send_item.cb.func(false, send_item.cb.para)
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
-- 本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

return tcp_ssl_ca_sender
