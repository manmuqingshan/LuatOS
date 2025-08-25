--[[
@module  tcp_client_receiver
@summary tcp client socket数据接收应用功能模块
@version 1.0
@date    2025.08.12
@author  孟伟
@usage
本文件为tcp client socket数据接收应用功能模块，核心业务逻辑为：
从内核读取接收到的数据，然后将数据处理后发送给其他应用功能模块做进一步处理；

本文件的对外接口有2个：
1、tcp_client_receiver.proc(socket_client)：数据接收应用逻辑处理入口，在tcp_client_main.lua中调用；
2、sys.publish("RECV_DATA_FROM_SERVER", data)：
   将接收到的数据通过消息"RECV_DATA_FROM_SERVER"发布出去处理；
   处理后通过消息"AIR_SRV_FOTA"发布到air_srv_fota.lua文件中去通知升级
]]

local tcp_client_receiver = {}

-- socket数据接收缓冲区
local recv_buff = nil

--[[
检查socket client是否收到数据，如果收到数据，读取并且处理完所有数据

@api tcp_client_receiver.proc(socket_client)

@param1 socket_client userdata
表示由socket.create接口创建的socket client对象；
必须传入，不允许为空或者nil；

@return1 result bool
表示处理结果，成功为true，失败为false

@usage
--
tcp_client_receiver.proc(socket_client)
]]
function tcp_client_receiver.proc(socket_client)
    -- 如果socket数据接收缓冲区还没有申请过空间，则先申请内存空间
    if recv_buff == nil then
        recv_buff = zbuff.create(1024)
        -- 当recv_buff不再使用时，不需要主动调用recv_buff:free()去释放
        -- 因为Lua的垃圾处理器会自动释放recv_buff所申请的内存空间
        -- 如果等不及垃圾处理器自动处理，在确定以后不会再使用recv_buff时，则可以主动调用recv_buff:free()释放内存空间
    end

    -- 循环从内核的缓冲区读取接收到的数据
    -- 如果读取失败，返回false，退出
    -- 如果读取成功，处理数据，并且继续循环读取
    -- 如果读取成功，并且读出来的数据为空，表示已经没有数据可读，返回true，退出
    while true do
        -- 从内核的缓冲区中读取数据到recv_buff中
        -- 如果recv_buff的存储空间不足，会自动扩容
        local result = socket.rx(socket_client, recv_buff)

        -- 读取数据失败
        -- 有两种情况：
        -- 1、recv_buff扩容失败
        -- 2、socket client和server之间的连接断开
        if not result then
            log.error("tcp_client_receiver.proc", "socket.rx error")
            return false
        end

        -- 如果读取到了数据, used()就必然大于0, 进行处理
        if recv_buff:used() > 0 then
            log.info("tcp_client_receiver.proc", "recv data len", recv_buff:used())

            -- 读取socket数据接收缓冲区中的数据，赋值给data
            local data = recv_buff:query()

            -- 将数据data通过"RECV_IOT_DATA_SERVER"消息publish出去，给其他应用模块处理
            sys.publish("RECV_IOT_DATA_SERVER", data)

            -- 清空socket数据接收缓冲区中的数据
            recv_buff:del()
            -- 读取成功，但是读出来的数据为空，表示已经没有数据可读，可以退出循环了
        else
            break
        end
    end

    return true
end

--解析接受到的json参数并发布到消息"AIR_SRV_FOTA"中
--定义一个json格式如下，具体可以根据实际情况定义，使用iot升级的话只定义了一个参数即可：
--{
--    "fota": "true"
--}

local function data_processing(data)
    -- 解析json数据
    local json_data = json.decode(data)
    -- 如果解析失败
    if not json_data then
        log.error("data_processing", "json.decode error")
        return
    end
    -- 如果fota为true
    if json_data.fota == "true" then
        -- 发布消息"AIR_SRV_FOTA"
        sys.publish("AIR_SRV_FOTA")
    end
end

-- 订阅"RECV_IOT_DATA_SERVER"消息
sys.subscribe("RECV_IOT_DATA_SERVER", data_processing)

return tcp_client_receiver
