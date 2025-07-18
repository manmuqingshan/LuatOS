--- 模块功能：Luat协程调度框架
--[[
@module sys
@summary LuaTask核心逻辑
@version 1.0
@date    2018.01.01
@author  稀饭/wendal/晨旭
@usage
-- sys一般会内嵌到固件内, 不需要手工添加到脚本列表,除非你正在修改sys.lua
-- 本文件修改后, 需要调用 update_lib_inline 对 vfs 中的C文件进行更新
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)
    log.info("sys", "say hi")
end)

sys.run()
]]

local sys = {}

local table = _G.table
local unpack = table.unpack
local rtos = _G.rtos
local coroutine = _G.coroutine
local log = _G.log

-- lib脚本版本号，只要lib中的任何一个脚本做了修改，都需要更新此版本号
SCRIPT_LIB_VER = "2.3.2"

-- TaskID最大值
local TASK_TIMER_ID_MAX = 0x1FFFFF
-- msgId 最大值(请勿修改否则会发生msgId碰撞的危险)
local MSG_TIMER_ID_MAX = 0x7FFFFF

-- 任务定时器id
local taskTimerId = 0
-- 消息定时器id
local msgId = TASK_TIMER_ID_MAX
-- 定时器id表
local timerPool = {}
--消息定时器参数表
local para = {}
--定时器是否循环表
--local loop = {}
--lua脚本运行出错时，是否回退为本地烧写的版本
--local sRollBack = true

_G.COROUTINE_ERROR_ROLL_BACK = true
_G.COROUTINE_ERROR_RESTART = true

-- 对coroutine.resume加一个修饰器用于捕获协程错误
--local rawcoresume = coroutine.resume
local function wrapper(co,...)
    local arg = {...}
    if not arg[1] then
        local traceBack = debug.traceback(co)
        traceBack = (traceBack and traceBack~="") and (arg[2].."\r\n"..traceBack) or arg[2]
        log.error("coroutine.resume",traceBack)
        --if errDump and type(errDump.appendErr)=="function" then
        --    errDump.appendErr(traceBack)
        --end
        if _G.COROUTINE_ERROR_ROLL_BACK then
            sys.timerStart(assert,500,false,traceBack)
        elseif _G.COROUTINE_ERROR_RESTART then
            rtos.reboot()
        end
    end
    return ...
end
sys.coresume = function(...)
    local arg = {...}
    return wrapper(arg[1], coroutine.resume(...))
end

function sys.check_task()
    local co, ismain = coroutine.running()
    if ismain then
        error(debug.traceback("attempt to yield from outside a coroutine"))
    end
    return co
end

--- Task任务延时函数，只能用于任务函数中
-- @number ms  整数，最大等待126322567毫秒
-- @return 定时结束返回nil,被其他线程唤起返回调用线程传入的参数
-- @usage sys.wait(30)
function sys.wait(ms)
    -- 参数检测，参数不能为负值
    --assert(ms > 0, "The wait time cannot be negative!")
    -- 选一个未使用的定时器ID给该任务线程
    local co = sys.check_task()
    while true do
        if taskTimerId >= TASK_TIMER_ID_MAX - 1 then
            taskTimerId = 0
        else
            taskTimerId = taskTimerId + 1
        end
        if timerPool[taskTimerId] == nil then
            break
        end
    end
    local timerid = taskTimerId
    timerPool[timerid] = co
    -- 调用core的rtos定时器
    if 1 ~= rtos.timer_start(timerid, ms) then log.debug("rtos.timer_start error") return end
    -- 挂起调用的任务线程
    local message = {coroutine.yield()}
    if #message ~= 0 then
        rtos.timer_stop(timerid)
        timerPool[timerid] = nil
        return unpack(message)
    end
end

--- Task任务的条件等待函数（包括事件消息和定时器消息等条件），只能用于任务函数中。
-- @param id 消息ID
-- @number ms 等待超时时间，单位ms，最大等待126322567毫秒
-- @return result 接收到消息返回true，超时返回false
-- @return data 接收到消息返回消息参数
-- @usage result, data = sys.waitUntil("SIM_IND", 120000)
function sys.waitUntil(id, ms)
    local co = sys.check_task()
    sys.subscribe(id, co)
    local message = ms and {sys.wait(ms)} or {coroutine.yield()}
    sys.unsubscribe(id, co)
    return message[1] ~= nil, unpack(message, 2, #message)
end

--- 同上，但不返回等待结果
function sys.waitUntilMsg(id)
    local co = sys.check_task()
    sys.subscribe(id, co)
    local message = {coroutine.yield()}
    sys.unsubscribe(id, co)
    return unpack(message, 2, #message)
end

--- Task任务的条件等待函数扩展（包括事件消息和定时器消息等条件），只能用于任务函数中。
-- @param id 消息ID
-- @number ms 等待超时时间，单位ms，最大等待126322567毫秒
-- @return message 接收到消息返回message，超时返回false
-- @return data 接收到消息返回消息参数
-- @usage result, data = sys.waitUntilExt("SIM_IND", 120000)
function sys.waitUntilExt(id, ms)
    local co = sys.check_task()
    sys.subscribe(id, co)
    local message = ms and {sys.wait(ms)} or {coroutine.yield()}
    sys.unsubscribe(id, co)
    if message[1] ~= nil then return unpack(message) end
    return false
end

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun 任务函数名，用于resume唤醒时调用
-- @param ... 任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sys.taskInit(task1,'a','b')
function sys.taskInit(fun, ...)
    local co = coroutine.create(fun)
    sys.coresume(co, ...)
    return co
end

------------------------------------------ rtos消息回调处理部分 ------------------------------------------
--[[
函数名：cmpTable
功能  ：比较两个table的内容是否相同，注意：table中不能再包含table
参数  ：
t1：第一个table
t2：第二个table
返回值：相同返回true，否则false
]]
local function cmpTable(t1, t2)
    if not t2 then return #t1 == 0 end
    if #t1 == #t2 then
        for i = 1, #t1 do
            if unpack(t1, i, i) ~= unpack(t2, i, i) then
                return false
            end
        end
        return true
    end
    return false
end

--- 关闭定时器
-- @param val 值为number时，识别为定时器ID，值为回调函数时，需要传参数
-- @param ... val值为函数时，函数的可变参数
-- @return 无
-- @usage timerStop(1)
function sys.timerStop(val, ...)
    -- val 为定时器ID
    if type(val) == 'number' then
        timerPool[val], para[val] = nil, nil
        rtos.timer_stop(val)
    else
        for k, v in pairs(timerPool) do
            -- 回调函数相同
            if type(v) == 'table' and v.cb == val or v == val then
                -- 可变参数相同
                if cmpTable({...}, para[k]) then
                    rtos.timer_stop(k)
                    timerPool[k], para[k] = nil, nil
                    break
                end
            end
        end
    end
end

--- 关闭同一回调函数的所有定时器
-- @param fnc 定时器回调函数
-- @return 无
-- @usage timerStopAll(cbFnc)
function sys.timerStopAll(fnc)
    for k, v in pairs(timerPool) do
        if type(v) == "table" and v.cb == fnc or v == fnc then
            rtos.timer_stop(k)
            timerPool[k], para[k] = nil, nil
        end
    end
end

function sys.timerAdvStart(fnc, ms, _repeat, ...)
    --回调函数和时长检测
    --assert(fnc ~= nil, "sys.timerStart(first param) is nil !")
    --assert(ms > 0, "sys.timerStart(Second parameter) is <= zero !")
    -- 关闭完全相同的定时器
    local arg = {...}
    if #arg == 0 then
        sys.timerStop(fnc)
    else
        sys.timerStop(fnc, ...)
    end
    -- 为定时器申请ID，ID值 1-20 留给任务，20-30留给消息专用定时器
    while true do
        if msgId >= MSG_TIMER_ID_MAX then msgId = TASK_TIMER_ID_MAX end
        msgId = msgId + 1
        if timerPool[msgId] == nil then
            timerPool[msgId] = fnc
            break
        end
    end
    --调用底层接口启动定时器
    if rtos.timer_start(msgId, ms, _repeat) ~= 1 then return end
    --如果存在可变参数，在定时器参数表中保存参数
    if #arg ~= 0 then
        para[msgId] = arg
    end
    --返回定时器id
    return msgId
end

--- 开启一个定时器
-- @param fnc 定时器回调函数
-- @number ms 整数，最大定时126322567毫秒
-- @param ... 可变参数 fnc的参数
-- @return number 定时器ID，如果失败，返回nil
function sys.timerStart(fnc, ms, ...)
    return sys.timerAdvStart(fnc, ms, 0, ...)
end

--- 开启一个循环定时器
-- @param fnc 定时器回调函数
-- @number ms 整数，最大定时126322567毫秒
-- @param ... 可变参数 fnc的参数
-- @return number 定时器ID，如果失败，返回nil
function sys.timerLoopStart(fnc, ms, ...)
    return sys.timerAdvStart(fnc, ms, -1, ...)
end

--- 判断某个定时器是否处于开启状态
-- @param val 有两种形式
--一种是开启定时器时返回的定时器id，此形式时不需要再传入可变参数...就能唯一标记一个定时器
--另一种是开启定时器时的回调函数，此形式时必须再传入可变参数...才能唯一标记一个定时器
-- @param ... 可变参数
-- @return number 开启状态返回true，否则nil
function sys.timerIsActive(val, ...)
    if type(val) == "number" then
        return timerPool[val]
    else
        for k, v in pairs(timerPool) do
            if v == val then
                if cmpTable({...}, para[k]) then return true end
            end
        end
    end
end


------------------------------------------ LUA应用消息订阅/发布接口 ------------------------------------------
-- 订阅者列表
local subscribers = {}
--内部消息队列
local messageQueue = {}

--- 订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage subscribe("NET_STATUS_IND", callback)
function sys.subscribe(id, callback)
    --if not id or type(id) == "boolean" or (type(callback) ~= "function" and type(callback) ~= "thread") then
    --    log.warn("warning: sys.subscribe invalid parameter", id, callback)
    --    return
    --end
    --log.debug("sys", "subscribe", id, callback)
    if type(id) == "table" then
        -- 支持多topic订阅
        for _, v in pairs(id) do sys.subscribe(v, callback) end
        return
    end
    if not subscribers[id] then subscribers[id] = {} end
    subscribers[id][callback] = true
end
--- 取消订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage unsubscribe("NET_STATUS_IND", callback)
function sys.unsubscribe(id, callback)
    --if not id or type(id) == "boolean" or (type(callback) ~= "function" and type(callback) ~= "thread") then
    --    log.warn("warning: sys.unsubscribe invalid parameter", id, callback)
    --    return
    --end
    --log.debug("sys", "unsubscribe", id, callback)
    if type(id) == "table" then
        -- 支持多topic订阅
        for _, v in pairs(id) do sys.unsubscribe(v, callback) end
        return
    end
    if subscribers[id] then subscribers[id][callback] = nil end
    -- 判断消息是否无其他订阅
    for k, _ in pairs(subscribers[id]) do
        return
    end
    subscribers[id] = nil
end

--- 发布内部消息，存储在内部消息队列中
-- @param ... 可变参数，用户自定义
-- @return 无
-- @usage publish("NET_STATUS_IND")
function sys.publish(...)
    table.insert(messageQueue, {...})
end

-- 分发消息
local function dispatch()
    while true do
        if #messageQueue == 0 then
            break
        end
        local message = table.remove(messageQueue, 1)
        if subscribers[message[1]] then
            local tmpt = {}
            for callback, _ in pairs(subscribers[message[1]]) do
                table.insert(tmpt, callback)
            end
            for _, callback in ipairs(tmpt) do
                if type(callback) == "function" then
                    callback(unpack(message, 2, #message))
                elseif type(callback) == "thread" then
                    sys.coresume(callback, unpack(message))
                end
            end
        end
    end
end

-- rtos消息回调
--local handlers = {}
--setmetatable(handlers, {__index = function() return function() end end, })

--- 注册rtos消息回调处理函数
-- @number id 消息类型id
-- @param handler 消息处理函数
-- @return 无
-- @usage rtos.on(rtos.MSG_KEYPAD, function(param) handle keypad message end)
--function sys.on(id, handler)
--    handlers[id] = handler
--end

------------------------------------------ Luat 主调度框架  ------------------------------------------
function sys.safeRun()
    -- 分发内部消息
    dispatch()
    -- 阻塞读取外部消息
    local msg, param, exparam = rtos.receive(rtos.INF_TIMEOUT)
    --log.info("sys", msg, param, exparam, tableNSize(timerPool), tableNSize(para), tableNSize(taskTimerPool), tableNSize(subscribers))
    -- 空消息?
    if not msg or msg == 0 then
        -- 无任何操作
    -- 判断是否为定时器消息，并且消息是否注册
    elseif msg == rtos.MSG_TIMER and timerPool[param] then
        if param < TASK_TIMER_ID_MAX then
            local taskId = timerPool[param]
            timerPool[param] = nil
            sys.coresume(taskId)
        else
            local cb = timerPool[param]
            --如果不是循环定时器，从定时器id表中删除此定时器
            if exparam == 0 then timerPool[param] = nil end
            if para[param] ~= nil then
                cb(unpack(para[param]))
                if exparam == 0 then para[param] = nil end
            else
                cb()
            end
            --如果是循环定时器，继续启动此定时器
            --if loop[param] then rtos.timer_start(param, loop[param]) end
        end
    --其他消息（音频消息、充电管理消息、按键消息等）
    --elseif type(msg) == "number" then
    --    handlers[msg](param, exparam)
    --else
    --    handlers[msg.id](msg)
    end
end

--- run()从底层获取core消息并及时处理相关消息，查询定时器并调度各注册成功的任务线程运行和挂起
-- @return 无
-- @usage sys.run()
if _G.SYSP then
    function sys.run() end
else
    function sys.run()
        while true do
            sys.safeRun()
        end
    end
end

_G.sys_pub = sys.publish

-- 并入原本的sysplus

----------------------------------------------
-- 提供给异步c接口使用, by 晨旭
sys.cwaitMt = {
    wait = function(t,r)
        return function()
            if r and type(r) == "table" then--新建等待失败的返回
                return table.unpack(r)
            end
            return sys.waitUntilMsg(t)
        end
    end,
    cb = function(t,r)
        return function(f)
            if type(f) ~= "function" then return end
            sys.taskInit(function ()
                if r and type(r) == "table" then
                    --sys.wait(1)--如果回调里调用了sys.publish，直接调用回调，会触发不了下一行的吧。。。
                    f(table.unpack(r))
                    return
                end
                f(sys.waitUntilMsg(t))
            end)
        end
    end,
}
sys.cwaitMt.__index = function(t,i)
    if sys.cwaitMt[i] then
        return sys.cwaitMt[i](rawget(t,"w"),rawget(t,"r"))
    else
        rawget(t,i)
    end
end
_G.sys_cw = function (w,...)
    local r = {...}
    local t = {w=w,r=(#r > 0 and r or nil)}
    setmetatable(t,sys.cwaitMt)
    return t
end

-------------------------------------------------------------------
------------- 基于任务的task扩展 by 李思琦---------------------------

--任务列表
local taskList = {}

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun 任务函数名，用于resume唤醒时调用
-- @param taskName 任务名称，用于唤醒任务的id
-- @param cbFun 接收到非目标消息时的回调函数
-- @param ... 任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sys.taskInitEx(task1,'a',callback)
function sys.taskInitEx(fun, taskName, cbFun, ...)
    taskList[taskName]={msgQueue={}, To=false, cb=cbFun}
    return sys.taskInit(fun, ...)
end

--- 删除由taskInitEx创建的任务线程
-- @param taskName 任务名称，用于唤醒任务的id
-- @return 无
-- @usage sys.taskDel('a')
function sys.taskDel(taskName)
    taskList[taskName]=nil
end

local function waitTo(taskName)
    taskList[taskName].To = true
    sys.publish(taskName)
end

--- 等待接收一个目标消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param target 目标消息，如果为nil，则表示接收到任意消息都会退出
-- @param ms 超时时间，如果为nil，则表示无超时，永远等待
-- @return msg or false 成功返回table型的msg，超时返回false
-- @usage sys.waitMsg('a', 'b', 1000)
function sys.waitMsg(taskName, target, ms)
    if taskList[taskName] == nil then
        log.error("sysplus", "sys.taskInitEx启动的task才能使用waitMsg")
        return false
    end
    local msg = false
    local message = nil
    if #taskList[taskName].msgQueue > 0 then
        msg = table.remove(taskList[taskName].msgQueue, 1)
        if target == nil then
            return msg
        end
        if (msg[1] == target) then
            return msg
        elseif type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
        end
    end
    sys.subscribe(taskName, coroutine.running())
    sys.timerStop(waitTo, taskName)
    if ms and ms ~= 0 then
        sys.timerStart(waitTo, ms, taskName)
    end
    taskList[taskName].To = false
    local finish=false
    while not finish do
        message = coroutine.yield()
        if #taskList[taskName].msgQueue > 0 then
            msg = table.remove(taskList[taskName].msgQueue, 1)
            -- sys.info("check target", msg[1], target)
            if target == nil then
                finish = true
            else
                if (msg[1] == target) then
                    finish = true
                elseif type(taskList[taskName].cb) == "function" then
                    taskList[taskName].cb(msg)
                end
            end
        elseif taskList[taskName].To then
            -- sys.info(taskName, "wait message timeout")
            finish = true
        end
    end
    if taskList[taskName].To then
        msg = nil
    end
    taskList[taskName].To = false
    sys.timerStop(waitTo, taskName)
    sys.unsubscribe(taskName, coroutine.running())
    return msg
end

--- 向目标任务发送一个消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param param1 消息中的参数1，同时也是waitMsg里的target
-- @param param2 消息中的参数2
-- @param param3 消息中的参数3
-- @param param4 消息中的参数4
-- @return true or false 成功返回true
-- @usage sys.sendMsg('a', 'b')
function sys.sendMsg(taskName, param1, param2, param3, param4)
    if taskList[taskName]~=nil then
        table.insert(taskList[taskName].msgQueue, {param1, param2, param3, param4})
        sys.publish(taskName)
        return true
    end
    return false
end

function sys.cleanMsg(taskName)
    if taskList[taskName]~=nil then
        taskList[taskName].msgQueue = {}
        return true
    end
    return false
end

function sys.taskCB(taskName, msg)
    if taskList[taskName]~=nil then
        if type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
            return
        end
    end
    log.error(taskName, "no cb fun")
end

_G.sys_send = sys.sendMsg
_G.sys_wait = sys.waitMsg

return sys
----------------------------
