# 实施计划：NES 按键模块重构 — GPIO 控制后装 APP

## 概述

重构 `nes_key_app.lua` 实现 8 方向计算、持续触发、A+B 组合键、软件防抖，后装 APP (`nes_emulator.lua`) 改为订阅全局事件而非直接注册 GPIO。触屏控件与实体按键共存。

## 事件协议设计

`nes_key_app` (工厂侧) 发布四类事件：

| 事件名 | 参数 | 触发时机 | 适用按键 |
|--------|------|----------|----------|
| `NES_KEY` | `key, pressed` | GPIO 边沿变化，立即发布 | A/B + 方向键个体事件 |
| `NES_DIR` | `direction` (0-8) | 方向组合状态变化时 | 上下左右组合（8方向） |
| `NES_CTRL` | `key` | 按下沿 + 软件防抖 | RETURN/START/SELECT |
| `NES_COMBO` | `combo` ("AB") | A+B 同时按下时 | A+B 组合 |

### direction 编码（顺时针）

| 值 | 方向 | bitmask (U/D/L/R) |
|----|------|-------------------|
| 0 | NONE | 0000 |
| 1 | UP | 0001 |
| 2 | UP_RIGHT | 1001 |
| 3 | RIGHT | 1000 |
| 4 | DOWN_RIGHT | 1010 |
| 5 | DOWN | 0010 |
| 6 | DOWN_LEFT | 0110 |
| 7 | LEFT | 0100 |
| 8 | UP_LEFT | 0101 |

### 按键类型自动分类（根据 key 名称）

- 包含 `NES_KEY_UP/DOWN/LEFT/RIGHT` → direction 类型
- 包含 `NES_KEY_A/B` → action 类型
- 包含 `NES_KEY_RETURN/START/SELECT` → control 类型

### A+B 组合检测策略（组合优先）

- A 按下后启动 200ms 定时器，暂不发布 NES_KEY
- 若 B 在 200ms 内按下 → 取消定时器，发布 NES_COMBO("AB")，进入 combo_active 状态
- combo_active 期间抑制所有 A/B 的 NES_KEY 事件
- 松开任一键 → 退出 combo，发布该键释放事件，若另一键仍按住则补发其 NES_KEY(1) 事件
- 若 200ms 内无第二键按下 → 定时器到期，正常发布 NES_KEY("A"/"B", 1)

### 软件防抖（控制键）

- 硬件层：`gpio.debounce(pin, 20, 1)` 处理电气抖动
- 软件层：同一键两次 NES_CTRL 发布间隔 ≥ 200ms

---

## 文件清单

### 修改的文件

- `C:\gitee\LuatOS\app_engine\factory\app\nes\nes_key_app.lua` — 核心重构
- `C:\gitee\LuatOS\app_engine\factory\config\eng_1602_5i_v3.lua` — 补充 RETURN/START/SELECT 按键
- `C:\gitee\LuatOS\app_engine\factory\config\template.lua` — 更新 nes_keys 文档
- `C:\Users\luat\Desktop\Jackal\user\nes_emulator.lua` — 移除 GPIO 注册，添加事件订阅

### 无需修改的文件

- `app_main.lua` — 已有的条件加载逻辑不变
- `platform_loader.lua` — 配置映射不变
- `eng_1602_7i_v4.lua` — 已有完整 9 键配置，无需改动
- `Jackal/main.lua` — 入口逻辑不变

---

## 任务

### 任务 1：更新配置模板文档

**文件：** `C:\gitee\LuatOS\app_engine\factory\config\template.lua`
**依赖：** 无

在 template.lua 的 nes_keys 示例中添加完整 9 键配置和文档说明。

**具体步骤：**

1. 读取 template.lua，找到 nes_keys 相关部分（约第 489-502 行）

2. 替换现有的 nes_keys 示例块为：

```lua
    -- NES游戏按键绑定（可选，GPIO引脚 → NES按键），不需要时设为 nil 或空数组
    -- 按键类型根据 key 名称自动分类：
    --   方向键: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    --           → 支持8方向组合（同时按两个相邻方向键=对角线方向）
    --           → 支持持续按住（nes_widget 状态型接口，无需重复发布）
    --   动作键: NES_KEY_A / NES_KEY_B
    --           → 单按 + A+B组合键（200ms内先后按下即触发）
    --           → 组合优先：同时按下时仅发布 NES_COMBO 事件
    --   控制键: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    --           → 仅单次触发 + 200ms软件防抖
    --
    -- key 完整可选值（按类型分组）：
    --   方向: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    --   动作: NES_KEY_A / NES_KEY_B
    --   控制: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        { pin =  1, key = "NES_KEY_RETURN" }, -- 返回（退出APP）
        { pin =  0, key = "NES_KEY_START" },  -- 开始
        { pin = 22, key = "NES_KEY_SELECT"},  -- 选择
        { pin = 23, key = "NES_KEY_A"     },  -- A
        { pin = 13, key = "NES_KEY_B"     },  -- B
    },
```

3. 在 features 表格中更新 nes 的说明：

找到 features 表格中的 `nes` 行，确保说明完整：

```lua
        nes = false,  -- 是否启用NES游戏按键GPIO绑定（需同时配置 nes_keys）
```

**验证：** 确认 template.lua 无语法错误，文档清晰完整。

---

### 任务 2：补充 5 寸型号的 NES 控制键

**文件：** `C:\gitee\LuatOS\app_engine\factory\config\eng_1602_5i_v3.lua`
**依赖：** 无

5 寸型号（Air1602 V003）目前 nes_keys 只有 6 个键（方向 4 个 + A/B），缺少 RETURN/START/SELECT。

**具体步骤：**

替换 nes_keys 块（约第 71-78 行）为：

```lua
    -- NES游戏按键绑定（GPIO引脚 → NES按键）
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        -- TODO: 以下三个引脚号需根据5寸底板实际接线确认
        { pin =  1, key = "NES_KEY_RETURN" },  -- 返回键（pin待确认）
        { pin =  0, key = "NES_KEY_START"  },  -- 开始键（pin待确认，当前与B冲突）
        { pin = 22, key = "NES_KEY_SELECT" },  -- 选择键（pin待确认）
        -- A/B 引脚从旧映射继承
        { pin = 23, key = "NES_KEY_A"      },  -- A（pin从0改为23，原0与START冲突）
        { pin = 13, key = "NES_KEY_B"      },  -- B（pin从1改为13，原1与RETURN冲突）
    },
```

**注意：** 5 寸型号原 A=pin0、B=pin1，新增 RETURN/START/SELECT 后引脚可能冲突。此配置将 A/B 移到 pin23/pin13（与 7 寸型号相同），但实际引脚需根据硬件确认。标记为 TODO。

**验证：** 确认 Lua 语法正确，配置 table 结构完整。

---

### 任务 3：重写 nes_key_app.lua

**文件：** `C:\gitee\LuatOS\app_engine\factory\app\nes\nes_key_app.lua`
**依赖：** 无

完整重写，实现：

- 按键类型自动分类（direction / action / control）
- 8 方向组合计算
- A+B 组合键检测（组合优先，200ms 窗口）
- 控制键软件防抖（200ms）
- 四类事件发布

**具体步骤：**

1. 读取当前 nes_key_app.lua 了解现有结构

2. 写入完整新内容：

```lua
--[[
@module  nes_key_app
@summary NES游戏按键模块 v3.0 — 8方向计算 + 持续触发 + A/B组合 + 防抖
@version 3.0
@date    2026.05.28

由 app_main 根据 project_config.features.nes 条件加载。
利用初始化流程订阅 OPEN_WELCOME_WIN 事件（LCD初始化后触发），延迟注册GPIO中断。

按键类型（根据 key 名称自动分类）：
  - 方向键: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    → 发布 NES_KEY(key, pressed) 单键事件 + 计算组合方向发布 NES_DIR(direction) 事件
  - 动作键: NES_KEY_A / NES_KEY_B
    → 200ms窗口内先后按下触发 NES_COMBO("AB")，否则发布 NES_KEY 事件
    → 组合优先：combo期间抑制单键事件
  - 控制键: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    → 仅按下沿发布 NES_CTRL(key)，200ms软件防抖

发布事件：
  NES_KEY(key, pressed)    — key="UP"/"DOWN"/"LEFT"/"RIGHT"/"A"/"B", pressed=1按下/0释放
  NES_DIR(direction)       — direction 0=NONE, 1=UP, 2=UP_RIGHT, 3=RIGHT, 4=DOWN_RIGHT,
                                    5=DOWN, 6=DOWN_LEFT, 7=LEFT, 8=UP_LEFT
  NES_CTRL(key)            — key="RETURN"/"START"/"SELECT"，仅按下时发布（带防抖）
  NES_COMBO(combo)         — combo="AB"，A和B同时按下时发布
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
        sys.publish("NES_DIR", new_code)
    end
end

-- ==================== GPIO 回调工厂 ====================

local function create_direction_callback(sname)
    local bit = DIR_NAME_TO_BIT[sname]
    return function(val)
        local pressed = (val == 0)
        if pressed then
            dir_bits = dir_bits | bit
        else
            dir_bits = dir_bits & ~bit
        end
        -- 单键事件（后装APP可选择性忽略，用NES_DIR替代）
        sys.publish("NES_KEY", sname, pressed and 1 or 0)
        -- 更新组合方向
        publish_direction()
    end
end

local function create_action_callback(sname)
    local is_a = (sname == "A")
    return function(val)
        local pressed = (val == 0)
        local now = mcu.ticks()

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
            local other_is = is_a and "B" or "A"
            local other_pressed = is_a and b_pressed or a_pressed

            if combo_active then
                -- 已在combo中，不应收到新的按下（除非硬件异常）
                return
            end

            if other_pressed then
                -- 另一键已按下，检查是否在combo窗口内
                local other_time = is_a and b_press_time or a_press_time
                if now - other_time <= COMBO_WINDOW_MS then
                    -- 触发组合！
                    -- 取消另一键的pending定时器
                    if pending_timer then
                        sys.timerStop(pending_timer)
                        pending_timer = nil
                    end
                    pending_action = nil
                    combo_active = true
                    sys.publish("NES_COMBO", "AB")
                    return
                end
                -- 超出窗口，正常发布单键事件
            end

            -- 第一键按下：启动combo等待定时器
            -- 定时器到期后才发布NES_KEY，给第二键留出combo窗口
            pending_action = sname
            if pending_timer then
                sys.timerStop(pending_timer)
            end
            pending_timer = sys.timerStart(function()
                if not combo_active and pending_action == sname then
                    sys.publish("NES_KEY", sname, 1)
                end
                pending_timer = nil
                pending_action = nil
            end, COMBO_WINDOW_MS)
        else
            -- === 释放事件 ===
            if combo_active then
                -- 从combo状态释放
                combo_active = false
                sys.publish("NES_KEY", sname, 0)
                -- 若另一键仍按住，补发其单独按下事件
                local other = is_a and "B" or "A"
                local other_held = is_a and b_pressed or a_pressed
                if other_held then
                    sys.publish("NES_KEY", other, 1)
                end
            else
                -- 取消pending（如果按键在combo窗口内就释放了）
                if pending_action == sname and pending_timer then
                    sys.timerStop(pending_timer)
                    pending_timer = nil
                    pending_action = nil
                else
                    -- 正常释放
                    sys.publish("NES_KEY", sname, 0)
                end
            end
        end
    end
end

local function create_control_callback(sname)
    return function(val)
        local pressed = (val == 0)
        if not pressed then return end  -- 控制键仅响应按下沿

        local now = mcu.ticks()
        local last = ctrl_last_press[sname] or 0
        if now - last >= CTRL_DEBOUNCE_MS then
            ctrl_last_press[sname] = now
            sys.publish("NES_CTRL", sname)
        end
    end
end

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
```

**验证：**
- 确认 Lua 语法正确（可先手动检查闭包引用）
- 确认 4 种事件类型都有 log 输出用于调试
- 确认 combo 逻辑覆盖：A先B后、B先A后、单按A、单按B、combo中释放

---

### 任务 4：改造后装 APP — 移除 GPIO 注册，添加事件订阅

**文件：** `C:\Users\luat\Desktop\Jackal\user\nes_emulator.lua`
**依赖：** 任务 3（nes_key_app 重写完成后才能测试）

改造 nes_emulator.lua：
1. 移除硬编码的 GPIO_KEY_MAP、setup_gpio_keys()、teardown_gpio_keys()
2. 添加 NES_DIR / NES_KEY / NES_CTRL / NES_COMBO 事件订阅
3. 保留所有触屏控件不变

**具体步骤：**

1. 删除以下代码块：
   - 第 54-61 行：`GPIO_KEY_MAP` 定义
   - 第 63-66 行：`use_gpio` 变量和 bsp 检测
   - 第 90-115 行：`DEBOUNCE_MS`、`setup_gpio_keys()`、`teardown_gpio_keys()` 函数

2. 删除以下调用点：
   - `launch_rom()` 中第 268 行的 `setup_gpio_keys()`
   - `stop_game()` 中第 145 行的 `teardown_gpio_keys()`
   - `request_exit()` 中第 165 行的 `teardown_gpio_keys()`

3. 在文件顶部（约第 18 行，`local nes_emulator = {}` 之后）添加事件订阅模块：

```lua
-- =========================================================
-- 实体按键事件订阅（由工厂 nes_key_app 通过全局消息发布）
-- =========================================================

-- 当前方向键在 NES 中的状态（用于 NES_DIR → nes_widget:key 的增量更新）
local entity_dir_state = { UP = false, DOWN = false, LEFT = false, RIGHT = false }

--- 方向映射表：direction编码 → {哪些方向键应按下}
local DIR_TO_KEYS = {
    [0] = {},                          -- NONE
    [1] = { UP = true },               -- UP
    [2] = { UP = true, RIGHT = true }, -- UP_RIGHT
    [3] = { RIGHT = true },            -- RIGHT
    [4] = { DOWN = true, RIGHT = true },-- DOWN_RIGHT
    [5] = { DOWN = true },             -- DOWN
    [6] = { DOWN = true, LEFT = true },-- DOWN_LEFT
    [7] = { LEFT = true },             -- LEFT
    [8] = { UP = true, LEFT = true },  -- UP_LEFT
}

--- 订阅：组合方向变化
sys.subscribe("NES_DIR", function(dir_code)
    if not nes_widget then return end

    local target = DIR_TO_KEYS[dir_code] or {}

    -- 释放不再按下的方向键
    for key, _ in pairs(entity_dir_state) do
        if entity_dir_state[key] and not target[key] then
            local key_code = airui["NES_KEY_" .. key]
            if key_code then
                nes_widget:key(key_code, 0)
            end
        end
    end

    -- 按下新激活的方向键
    for key, _ in pairs(target) do
        if target[key] and not entity_dir_state[key] then
            local key_code = airui["NES_KEY_" .. key]
            if key_code then
                nes_widget:key(key_code, 1)
            end
        end
    end

    entity_dir_state = target
end)

--- 订阅：单键事件（仅处理 A/B，方向键由 NES_DIR 统一管理）
sys.subscribe("NES_KEY", function(key, pressed)
    if key ~= "A" and key ~= "B" then return end
    if not nes_widget then return end

    local key_code = airui["NES_KEY_" .. key]
    if key_code then
        nes_widget:key(key_code, pressed)
    end
end)

--- 订阅：控制键（RETURN/START/SELECT）
sys.subscribe("NES_CTRL", function(key)
    if key == "RETURN" then
        -- 在游戏运行屏 → 返回选择屏；在选择屏 → 退出应用
        if nes_widget then
            -- 游戏中：停止游戏，回到ROM选择屏
            log.info("nes_emu", "entity key RETURN -> stop game")
            stop_game()
        else
            -- 选择屏：退出应用
            log.info("nes_emu", "entity key RETURN -> exit app")
            request_exit()
        end
    elseif key == "START" then
        if nes_widget then
            nes_widget:key(airui.NES_KEY_START, 1)
            sys.timerStart(function()
                if nes_widget then
                    nes_widget:key(airui.NES_KEY_START, 0)
                end
            end, 80)
        end
    elseif key == "SELECT" then
        if nes_widget then
            nes_widget:key(airui.NES_KEY_SELECT, 1)
            sys.timerStart(function()
                if nes_widget then
                    nes_widget:key(airui.NES_KEY_SELECT, 0)
                end
            end, 80)
        end
    end
end)

--- 订阅：A+B组合键
sys.subscribe("NES_COMBO", function(combo)
    if combo == "AB" and nes_widget then
        -- 组合键：同时设置 A 和 B 为按下状态（用于Nes游戏中的特殊操作）
        nes_widget:key(airui.NES_KEY_A, 1)
        nes_widget:key(airui.NES_KEY_B, 1)
        log.info("nes_emu", "A+B combo -> both pressed")
    end
end)
```

4. 在 `on_destroy()` 中不需要手动取消订阅（exapp 沙箱退出时自动清理）

**验证：**
- 确认触屏按钮功能不受影响
- 确认实体按键事件能正确驱动游戏
- 确认 RETURN 键在游戏中和选择屏中的行为不同（游戏中→返回选择，选择屏→退出）

---

### 任务 5：联调验证

**依赖：** 任务 1-4 全部完成

在设备上烧录固件后验证以下场景：

**方向键测试：**
- [ ] 按上 → 角色上移
- [ ] 按右 → 角色右移
- [ ] 同时按上+右 → 角色右上对角移动
- [ ] 持续按住上 → 角色持续上移（不松手）
- [ ] 松开上 → 角色停止

**动作键测试：**
- [ ] 单独按 A → 触发 A 动作
- [ ] 单独按 B → 触发 B 动作
- [ ] A+B 同时按（200ms内） → 触发组合，NES 中 A 和 B 同时为按下状态
- [ ] 从组合松开 B → A 恢复单独生效
- [ ] 从组合松开 A → B 恢复单独生效

**控制键测试：**
- [ ] 游戏中选择屏按 RETURN → 退出 APP
- [ ] 游戏运行中按 RETURN → 返回 ROM 选择屏
- [ ] 游戏中按 START → 触发 START（如暂停/开始）
- [ ] 快速连按 START → 无重复触发（防抖生效）
- [ ] 游戏中按 SELECT → 触发 SELECT

**触屏共存测试：**
- [ ] 触屏 D-pad 仍然正常工作
- [ ] 触屏和实体按键可交替使用，互不干扰
- [ ] Back 按钮（触屏）仍然正常工作

**边界情况：**
- [ ] 无 nes_keys 配置的平台 → nes_key_app 静默跳过，不影响系统
- [ ] features.nes = false → nes_key_app 不加载
- [ ] 同时按上下两个相反方向 → 方向抵消为 NONE
- [ ] 同时按左右两个相反方向 → 方向抵消为 NONE

---

## 补充说明

### 5 寸型号 GPIO 引脚确认

`eng_1602_5i_v3.lua` 中的 RETURN/START/SELECT 引脚已标记 TODO。需要根据 5 寸底板原理图确认实际引脚号。当前暂用与 7 寸相同的引脚（RETURN=1, START=0, SELECT=22），同时将 A/B 移至 23/13。如实际硬件不同，修改 `nes_keys` 数组即可，`nes_key_app.lua` 代码无需改动。

### combo 窗口时序说明

A+B 组合键使用 200ms 检测窗口：
1. A 按下 → 启动 200ms 定时器（暂不发 NES_KEY）
2. 若 B 在 200ms 内按下 → 取消定时器，发 NES_COMBO("AB")
3. 若 200ms 到期 → 发 NES_KEY("A", 1)，后续 B 按下正常发 NES_KEY("B", 1)

这意味着单按 A 会有最多 200ms 的延迟。如果应用对 A/B 响应延迟敏感，可调小 COMBO_WINDOW_MS（如 150ms 或 100ms）。
