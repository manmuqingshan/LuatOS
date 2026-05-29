--[[
@module  nes_key_app
@summary NES游戏按键模块 v3.0 — 8方向计算 + 持续触发 + A/B组合 + 防抖
@version 3.0
@date    2026.05.30
@author  江访

由 app_main 根据 project_config.features.nes 条件加载。
订阅 OPEN_WELCOME_WIN 事件（LCD初始化后触发），延迟注册GPIO中断。

按键类型（根据 key 名称自动分类）：
  - 方向键: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    → 发布 NES_KEY(key, pressed) 单键事件 + 计算组合方向发布 NES_DIR(direction) 事件
    → 支持8方向组合（同时按两个相邻方向键=对角线方向）
  - 动作键: NES_KEY_A / NES_KEY_B
    → 200ms窗口内先后按下触发 NES_COMBO("AB")，否则发布 NES_KEY 事件
    → 组合优先：combo期间抑制单键事件
  - 控制键: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    → 仅按下沿发布 NES_CTRL(key)，200ms软件防抖

发布事件：
  NES_KEY(key, pressed)    — key="UP"/"DOWN"/"LEFT"/"RIGHT"/"A"/"B", pressed=1按下/0释放
  NES_DIR(direction)       — 0=NONE, 1=UP, 2=UP_RIGHT, 3=RIGHT, 4=DOWN_RIGHT,
                                    5=DOWN, 6=DOWN_LEFT, 7=LEFT, 8=UP_LEFT
  NES_CTRL(key)            — key="RETURN"/"START"/"SELECT"，仅按下沿发布（带防抖）
  NES_COMBO(combo)         — combo="AB"，A和B同时按下时发布

通信（兼容旧接口）：
  APP 发 NES_APP_BIND → 引擎读 _G.NES_KEY_CONFIG（优先）
                        → 回退 project_config.nes_keys
                        → 发 NES_KEY_CFG(cfg)
]]

-- ==================== 配置常量 ====================

local HW_DEBOUNCE_MS = 20          -- GPIO硬件消抖(ms)
local CTRL_DEBOUNCE_MS = 200       -- 控制键软件防抖窗口(ms)
local COMBO_WINDOW_MS = 200        -- A+B组合键检测窗口(ms)

-- ==================== 方向状态 ====================

-- 方向bitmask: bit0=UP, bit1=DOWN, bit2=LEFT, bit3=RIGHT
local dir_bits = 0
local prev_dir_code = 0

-- bitmask → 方向编码（顺时针）
local DIR_BITMASK_TO_CODE = {
    [0]  = 0,   -- NONE
    [1]  = 1,   -- UP         (0b0001)
    [2]  = 5,   -- DOWN       (0b0010)
    [4]  = 7,   -- LEFT       (0b0100)
    [8]  = 3,   -- RIGHT      (0b1000)
    [5]  = 8,   -- UP+LEFT    (0b0101)
    [9]  = 2,   -- UP+RIGHT   (0b1001)
    [6]  = 6,   -- DOWN+LEFT  (0b0110)
    [10] = 4,   -- DOWN+RIGHT (0b1010)
    [3]  = 0,   -- UP+DOWN    → 抵消为NONE
    [12] = 0,   -- LEFT+RIGHT → 抵消为NONE
}

-- 方向键短名 → bit位
local DIR_NAME_TO_BIT = {
    UP    = 1,   -- bit0
    DOWN  = 2,   -- bit1
    LEFT  = 4,   -- bit2
    RIGHT = 8,   -- bit3
}

-- ==================== 动作键(A/B)状态 ====================

local a_pressed = false
local b_pressed = false
local a_press_time = 0
local b_press_time = 0
local combo_active = false
local pending_action = nil    -- 等待combo窗口的按键名 ("A" or "B")
local pending_timer = nil     -- 等待combo窗口的定时器ID

-- ==================== 控制键状态 ====================

local ctrl_last_press = {}    -- key短名 → 上次按下时间戳(ms)

-- ==================== 工具函数 ====================

--- 从 NES_KEY_XXX 全名提取短名（如 "NES_KEY_UP" → "UP"）
local function short_name(key_name)
    return key_name:match("NES_KEY_(.+)$") or key_name
end

--- 按键类型分类
local function classify_key(key_name)
    if key_name:find("NES_KEY_UP") or key_name:find("NES_KEY_DOWN") or
       key_name:find("NES_KEY_LEFT") or key_name:find("NES_KEY_RIGHT") then
        return "direction"
    end
    if key_name:find("NES_KEY_A") or key_name:find("NES_KEY_B") then
        return "action"
    end
    if key_name:find("NES_KEY_RETURN") or key_name:find("NES_KEY_START") or
       key_name:find("NES_KEY_SELECT") then
        return "control"
    end
    return "unknown"
end

--- 计算并发布组合方向（仅当方向状态变化时）
local function publish_direction()
    local new_code = DIR_BITMASK_TO_CODE[dir_bits]
    if new_code == nil then new_code = 0 end
    if new_code ~= prev_dir_code then
        prev_dir_code = new_code
        log.info("nes_key", "DIR publish NES_DIR", new_code)
        sys.publish("NES_DIR", new_code)
    end
end

-- ==================== GPIO 回调工厂 ====================

--- 方向键回调：更新 bitmask，发布 NES_KEY + 计算 NES_DIR
local function create_direction_callback(sname)
    local bit = DIR_NAME_TO_BIT[sname]
    return function(val)
        local pressed = (val == 0)
        log.info("nes_key", "DIR GPIO", sname, pressed and "DOWN" or "UP", "bits before", dir_bits)
        if pressed then
            dir_bits = dir_bits | bit
        else
            dir_bits = dir_bits & ~bit
        end
        -- 单键事件（后装APP可选择性忽略，用NES_DIR替代）
        sys.publish("NES_KEY", sname, pressed and 1 or 0)
        -- 更新组合方向
        publish_direction()
        log.info("nes_key", "DIR publish NES_KEY", sname, pressed and 1 or 0, "dir_bits", dir_bits)
    end
end

--- 动作键回调：A/B 组合窗口检测（组合优先）
local function create_action_callback(sname)
    local is_a = (sname == "A")
    return function(val)
        local pressed = (val == 0)
        local now = mcu.ticks()
        log.info("nes_key", "ACT GPIO", sname, pressed and "DOWN" or "UP", "tick", now)

        -- 更新状态
        if is_a then
            a_pressed = pressed
            if pressed then a_press_time = now end
        else
            b_pressed = pressed
            if pressed then b_press_time = now end
        end

        if pressed then
            -- === 按下事件 ===
            local other_pressed = is_a and b_pressed or a_pressed

            if combo_active then
                log.info("nes_key", "ACT combo_active, ignore", sname)
                return
            end

            if other_pressed then
                local other_time = is_a and b_press_time or a_press_time
                if now - other_time <= COMBO_WINDOW_MS then
                    if pending_timer then
                        sys.timerStop(pending_timer)
                        pending_timer = nil
                    end
                    pending_action = nil
                    combo_active = true
                    log.info("nes_key", "ACT publish NES_COMBO AB")
                    sys.publish("NES_COMBO", "AB")
                    return
                end
            end

            pending_action = sname
            if pending_timer then
                sys.timerStop(pending_timer)
            end
            pending_timer = sys.timerStart(function()
                if not combo_active and pending_action == sname then
                    log.info("nes_key", "ACT timer publish NES_KEY", sname, 1)
                    sys.publish("NES_KEY", sname, 1)
                end
                pending_timer = nil
                pending_action = nil
            end, COMBO_WINDOW_MS)
        else
            -- === 释放事件 ===
            if combo_active then
                combo_active = false
                log.info("nes_key", "ACT combo release", sname)
                sys.publish("NES_KEY", sname, 0)
                local other = is_a and "B" or "A"
                local other_held = is_a and b_pressed or a_pressed
                if other_held then
                    log.info("nes_key", "ACT combo release, restore", other)
                    sys.publish("NES_KEY", other, 1)
                end
            else
                if pending_action == sname and pending_timer then
                    sys.timerStop(pending_timer)
                    pending_timer = nil
                    pending_action = nil
                else
                    log.info("nes_key", "ACT publish NES_KEY", sname, 0)
                    sys.publish("NES_KEY", sname, 0)
                end
            end
        end
    end
end

--- 控制键回调：仅按下沿 + 200ms软件防抖
local function create_control_callback(sname)
    return function(val)
        local pressed = (val == 0)
        if not pressed then return end  -- 控制键仅响应按下沿

        local now = mcu.ticks()
        local last = ctrl_last_press[sname] or 0
        if now - last >= CTRL_DEBOUNCE_MS then
            ctrl_last_press[sname] = now
            log.info("nes_key", "CTRL publish NES_CTRL", sname)
            sys.publish("NES_CTRL", sname)
        end
    end
end

-- ==================== 配置传递（兼容旧接口） ====================

sys.subscribe("NES_APP_BIND", function()
    local cfg = _G.NES_KEY_CONFIG
    if not cfg or type(cfg) ~= "table" or #cfg == 0 then
        local pc = _G.project_config
        if pc and pc.nes_keys and type(pc.nes_keys) == "table" then
            cfg = pc.nes_keys
        end
    end
    if cfg and type(cfg) == "table" and #cfg > 0 then
        log.info("nes_key_app", "send NES_KEY_CFG", #cfg, "keys")
        sys.publish("NES_KEY_CFG", cfg)
    end
end)

-- ==================== 主初始化（延迟到LCD就绪后） ====================

sys.subscribe("OPEN_WELCOME_WIN", function()
    local cfg = _G.project_config
    if not cfg or not cfg.nes_keys or type(cfg.nes_keys) ~= "table" then
        log.info("nes_key_app", "no nes_keys in config, skip")
        return
    end

    local count = 0
    for _, entry in ipairs(cfg.nes_keys) do
        local pin = entry.pin
        local key_name = entry.key
        local key_type = classify_key(key_name)
        local sname = short_name(key_name)

        if key_type == "unknown" then
            log.warn("nes_key_app", "unknown key type:", key_name, "-> GPIO", pin)
        end

        -- 硬件消抖
        gpio.debounce(pin, HW_DEBOUNCE_MS, 1)

        -- 根据类型创建对应的回调
        local callback
        if key_type == "direction" then
            callback = create_direction_callback(sname)
        elseif key_type == "action" then
            callback = create_action_callback(sname)
        elseif key_type == "control" then
            callback = create_control_callback(sname)
        else
            -- unknown类型：降级为简单双边沿发布
            callback = function(val)
                sys.publish("NES_KEY", sname, val == 0 and 1 or 0)
            end
        end

        gpio.setup(pin, callback, gpio.PULLUP, gpio.BOTH)

        count = count + 1
        log.info("nes_key_app", key_name, "(", key_type, ")", "-> GPIO", pin)
    end
    log.info("nes_key_app", "registered", count, "NES keys")
end)
