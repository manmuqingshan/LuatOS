-- school_bus_win.lua - 智慧校车刷卡系统
local school_bus_win = {}

-- ==================== 常量定义 ====================
local SCREEN_W, SCREEN_H = 480, 800

local C = {
    PRIMARY = 0x2B7E3A,
    BG_MAIN = 0xF9FBFE,
    BG_CARD = 0xFFFFFF,
    TEXT_PRIMARY = 0x1E293B,
    TEXT_SECONDARY = 0x4B556B,
    TEXT_LIGHT = 0x94A3B8,
    STATUS_BG = 0xF0F2F5,
    ACTIVE_BG = 0x2B7E3A,
    INACTIVE_BG = 0xFFFFFF,
    ACTIVE_TEXT = 0xFFFFFF,
    INACTIVE_TEXT = 0x64748B,
    DANGER = 0xDC2626,
    WARNING = 0xF97316,
    INFO = 0x10B981,
    BLUE = 0x3B82F6,
    BORDER = 0xE6EDF4
}

-- 窗口ID
local win_id = nil

-- 定时器ID列表
local timers = {}

-- 页面容器
local root_container = nil
local card_area = nil
local card_status_label = nil
local info_panel_bg = nil
local student_info_container = nil
local direction_badge = nil
local record_list_area = nil

-- 当前乘车信息中的标签引用
local current_info_labels = {}

-- 时间显示标签
local time_label = nil

-- 记录项UI引用列表
local record_items = {}

-- ==================== 学生数据库 ====================
local STUDENTS_DB = {
    { id = "20240001", name = "张子轩", grade = "五年级(3)班", guardian = "张先生", cardUid = "A1B2C3D4" },
    { id = "20240012", name = "李雨桐", grade = "四年级(2)班", guardian = "李女士", cardUid = "E5F6G7H8" },
    { id = "20240023", name = "王明远", grade = "六年级(1)班", guardian = "王先生", cardUid = "I9J0K1L2" },
    { id = "20240034", name = "陈思琪", grade = "三年级(4)班", guardian = "陈女士", cardUid = "M3N4O5P6" },
    { id = "20240045", name = "赵子涵", grade = "二年级(5)班", guardian = "赵先生", cardUid = "Q7R8S9T0" },
    { id = "20240056", name = "周子衡", grade = "一年级(2)班", guardian = "周女士", cardUid = "U1V2W3X4" },
    { id = "20240067", name = "吴佳怡", grade = "五年级(1)班", guardian = "吴先生", cardUid = "Y5Z6A7B8" }
}

local card_to_student_map = {}
for _, student in ipairs(STUDENTS_DB) do
    card_to_student_map[student.cardUid] = student
end

-- 体验卡
card_to_student_map["TESTCARD"] = {
    id = "DEMO999",
    name = "体验卡",
    grade = "访客卡",
    guardian = "临时卡",
    cardUid = "TESTCARD",
    is_special = true
}

-- 乘车记录
local ride_records = {}

-- ==================== fskv 数据存储 ====================
local function init_fskv()
    local result = fskv.init()
    if result then
        log.info("fskv", "kv数据库初始化成功")
    else
        log.warn("fskv", "kv数据库初始化失败")
    end
    return result
end

local function save_records()
    fskv.set("bus_ride_records", ride_records)
end

local function load_records()
    local data = fskv.get("bus_ride_records")
    if data and type(data) == "table" then
        ride_records = data
        return true
    end
    return false
end

-- ==================== 辅助函数 ====================
local function add_timer(id)
    table.insert(timers, id)
end

local function stop_all_timers()
    for _, id in ipairs(timers) do
        sys.timerStop(id)
    end
    timers = {}
end

local function get_time()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour, t.min)
end

local function get_full_time()
    return os.date("%H:%M:%S")
end

-- ==================== Toast提示 ====================
local toast_timer = nil
local current_toast = nil

local function show_toast(msg, is_error)
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if current_toast then
        pcall(function()
            current_toast:destroy()
        end)
        current_toast = nil
    end
    if not root_container then
        return
    end

    local bg_color = is_error and 0xDC2626 or 0x1E293B

    current_toast = airui.container({
        parent = root_container,
        x = SCREEN_W / 2 - 130,
        y = SCREEN_H - 100,
        w = 260,
        h = 40,
        color = bg_color,
        radius = 20
    })
    airui.label({
        parent = current_toast,
        x = 0,
        y = 8,
        w = 260,
        h = 24,
        text = msg,
        font_size = 13,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    toast_timer = sys.timerStart(function()
        if current_toast then
            pcall(function()
                current_toast:destroy()
            end)
            current_toast = nil
        end
        toast_timer = nil
    end, 2000)
end

-- ==================== 记录列表刷新 ====================
local function refresh_record_list()
    if not record_list_area then
        return
    end

    -- 销毁旧的记录项
    for _, item in ipairs(record_items) do
        pcall(function()
            item:destroy()
        end)
    end
    record_items = {}

    if #ride_records == 0 then
        local empty_label = airui.label({
            parent = record_list_area,
            x = 0,
            y = 20,
            w = 430,
            h = 30,
            text = "暂无刷卡记录",
            font_size = 13,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(record_items, empty_label)
        return
    end

    local y_offset = 0
    local max_records = math.min(#ride_records, 8)
    
    for i = 1, max_records do
        local record = ride_records[i]
        local is_up = (record.action == "上车")
        
        local item = airui.container({
            parent = record_list_area,
            x = 0,
            y = y_offset,
            w = 430,
            h = 44,
            color = C.BG_CARD,
            border_width = 1,
            border_color = C.BORDER,
            border_side = 2
        })

        -- 姓名
        airui.label({
            parent = item,
            x = 16,
            y = 12,
            w = 120,
            h = 22,
            text = record.student_name,
            font_size = 14,
            color = C.TEXT_PRIMARY
        })

        -- 动作标签
        local action_color = is_up and C.INFO or C.WARNING
        local action_text = is_up and "上车" or "下车"
        airui.label({
            parent = item,
            x = 140,
            y = 12,
            w = 50,
            h = 22,
            text = action_text,
            font_size = 12,
            color = action_color,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 时间
        airui.label({
            parent = item,
            x = 302,
            y = 12,
            w = 70,
            h = 22,
            text = record.time_str,
            font_size = 11,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_RIGHT
        })

        table.insert(record_items, item)
        y_offset = y_offset + 43
    end
end

-- ==================== 添加记录 ====================
local function add_record(student, action)
    local record = {
        student_name = student.name,
        student_id = student.id,
        action = action,
        time_str = get_full_time(),
        timestamp = os.time(),
        cardUid = student.cardUid
    }
    table.insert(ride_records, 1, record)
    
    -- 保持最多20条记录
    while #ride_records > 20 do
        table.remove(ride_records)
    end
    
    save_records()
    refresh_record_list()
end

-- ==================== 刷新当前乘车信息面板 ====================
local function refresh_info_panel(student, action, is_unknown, is_special)
    if not student_info_container then
        return
    end

    -- 销毁旧的标签
    for _, label in ipairs(current_info_labels) do
        pcall(function()
            label:destroy()
        end)
    end
    current_info_labels = {}

    local y_offset = 0
    
    if is_unknown then
        -- 未知卡片显示
        local name_label = airui.label({
            parent = student_info_container,
            x = 0,
            y = y_offset,
            w = SCREEN_W - 96,
            h = 32,
            text = "未授权卡片",
            font_size = 24,
            color = 0xD97706,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, name_label)
        y_offset = y_offset + 40
        
        local line = airui.container({
            parent = student_info_container,
            x = 0,
            y = y_offset,
            w = SCREEN_W - 96,
            h = 1,
            color = 0xEEF2FF
        })
        table.insert(current_info_labels, line)
        y_offset = y_offset + 12
        
        local uid_label = airui.label({
            parent = student_info_container,
            x = 0,
            y = y_offset,
            w = SCREEN_W - 96,
            h = 28,
            text = "UID: " .. (student.cardUid or "未知"),
            font_size = 13,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, uid_label)
        y_offset = y_offset + 32
        
        local tip_label = airui.label({
            parent = student_info_container,
            x = 0,
            y = y_offset,
            w = SCREEN_W - 96,
            h = 28,
            text = "请至校车老师处登记",
            font_size = 13,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, tip_label)
        y_offset = y_offset + 32
        
        local action_label = airui.label({
            parent = student_info_container,
            x = 0,
            y = y_offset,
            w = SCREEN_W - 96,
            h = 24,
            text = "刷卡动作: " .. action .. " (无记录)",
            font_size = 12,
            color = C.TEXT_LIGHT,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, action_label)
        return
    end
    
    -- 特殊卡片显示（体验卡）
    if is_special then
        local name_label = airui.label({
            parent = student_info_container,
            x = 0,
            y = 0,
            w = 360,
            h = 30,
            text = student.name,
            font_size = 28,
            color = C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, name_label)
        
        local line = airui.container({
            parent = student_info_container,
            x = 20,
            y = 32,
            w = 360,
            h = 1,
            color = 0xEEF2FF
        })
        table.insert(current_info_labels, line)
        
        local info_row = airui.container({
            parent = student_info_container,
            x = 3,
            y = 35,
            w = 380,
            h = 100,
            color = C.BG_CARD
        })
        table.insert(current_info_labels, info_row)
        
        -- 班级行：添加图片
        airui.image({
            parent = info_row,
            src = "/luadb/school_20x20.png",
            x = 5,
            y = 0,
            w = 20,
            h = 20,
            zoom = 256,
            opacity = 255
        })
        
        airui.label({
            parent = info_row,
            x = 30,
            y = 5,
            w = 120,
            h = 25,
            text = "班  级 : " .. student.grade,
            font_size = 15,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        -- 监护人行：添加 family_guardian_20x20.png 图片
        airui.image({
            parent = info_row,
            src = "/luadb/family_guardian_20x20.png",
            x = 5,
            y = 37,
            w = 20,
            h = 20,
            zoom = 256,
            opacity = 255
        })
        
        airui.label({
            parent = info_row,
            text = "监护人 : " .. student.guardian,
            x = 30,
            y = 35,
            w = 160,
            h = 22,
            font_size = 15,
            color = C.TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        -- 上车/下车记录行：添加 card_20x20.png 图片
        airui.image({
            parent = info_row,
            src = "/luadb/card_20x20.png",
            x = 5,
            y = 76,
            w = 20,
            h = 20,
            zoom = 256,
            opacity = 255
        })
        
        local action_label = airui.label({
            parent = info_row,
            x = 30,
            y = 80,
            w = 100,
            h = 20,
            text = action .. "记录",
            font_size = 14,
            color = C.TEXT_PRIMARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, action_label)
        
        local divider = airui.container({
            parent = student_info_container,
            x = 20,
            y = 135,
            w = 360,
            h = 1,
            color = 0xEEF2FF
        })
        table.insert(current_info_labels, divider)
        
        
        local time_label_info = airui.label({
            parent = student_info_container,
            x = 10,
            y = 140,
            w = 300,
            h = 24,
            text = "刷卡时间 : " .. get_full_time(),
            font_size = 12,
            color = 0x6181B4,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(current_info_labels, time_label_info)
        return
    end
    
    -- 普通学生卡片显示
    local name_label = airui.label({
        parent = student_info_container,
        x = 0,
        y = 0,
        w = 360,
        h = 28,
        text = student.name,
        font_size = 28,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    table.insert(current_info_labels, name_label)
    
    local line = airui.container({
        parent = student_info_container,
        x = 0,
        y = 32,
        w = 360,
        h = 1,
        color = 0xEEF2FF
    })
    table.insert(current_info_labels, line)
    
    local info_row = airui.container({
        parent = student_info_container,
        x = 3,
        y = 35,
        w = 380,
        h = 100,
        color = C.BG_CARD
    })
    table.insert(current_info_labels, info_row)
    
    -- 班级行：添加 school_20x20.png 图片
    airui.image({
        parent = info_row,
        src = "/luadb/school_20x20.png",
        x = 5,
        y = 0,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = info_row,
        x = 30,
        y = 5,
        w = 150,
        h = 25,
        text = "班级:" .. student.grade,
        font_size = 15,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 监护人行：添加 family_guardian_20x20.png 图片
    airui.image({
        parent = info_row,
        src = "/luadb/family_guardian_20x20.png",
        x = 5,
        y = 37,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = info_row,
        x = 30,
        y = 35,
        w = 160,
        h = 22,
        text = "监护人:" .. student.guardian,
        font_size = 15,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 上车/下车记录行：添加 card_20x20.png 图片
    airui.image({
        parent = info_row,
        src = "/luadb/card_20x20.png",
        x = 5,
        y = 76,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    local action_label = airui.label({
        parent = info_row,
        x = 30,
        y = 80,
        w = 100,
        h = 20,
        text = action .. "记录",
        font_size = 14,
        color = C.TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    table.insert(current_info_labels, action_label)
    
    local divider = airui.container({
        parent = student_info_container,
        x = 20,
        y = 135,
        w = 360,
        h = 1,
        color = 0xEEF2FF
    })
    table.insert(current_info_labels, divider)
    
    
    local time_label_info = airui.label({
        parent = student_info_container,
        x = 10,
        y = 140,
        w = 300,
        h = 24,
        text = "刷卡时间 " .. get_full_time(),
        font_size = 12,
        color = 0x6181B4,
        align = airui.TEXT_ALIGN_LEFT
    })
    table.insert(current_info_labels, time_label_info)
end

-- ==================== 更新方向标签（带图片） ====================
local function update_direction_badge(action)
    if not direction_badge then
        return
    end
    
    -- 先销毁旧的direction_badge内容
    pcall(function()
        direction_badge:destroy()
    end)
    
    -- 重新创建带图片的方向标签
    local badge_x = SCREEN_W - 200
    local badge_y = 13
    
    direction_badge = airui.container({
        parent = info_panel_bg,
        x = badge_x,
        y = badge_y,
        w = 100,
        h = 24,
        color = 0xEEF2FF,
        radius = 60
    })
    
    -- 根据动作添加对应的图片
    if action == "上车" then
        airui.image({
            parent = direction_badge,
            src = "/luadb/arrow_up_20x20.png",
            x = 8,
            y = 2,
            w = 20,
            h = 20,
            zoom = 256,
            opacity = 255
        })
    elseif action == "下车" then
        airui.image({
            parent = direction_badge,
            src = "/luadb/arrow_down_20x20.png",
            x = 8,
            y = 2,
            w = 20,
            h = 20,
            zoom = 256,
            opacity = 255
        })
    end
    
    local text_x = action == "上车" or action == "下车" 
    airui.label({
        parent = direction_badge,
        x = 32,
        y = 2,
        w = 60,
        h = 20,
        text = action == "上车" and "上车" or (action == "下车" and "下车" or "上下车"),
        font_size = 12,
        color = action == "上车" and C.INFO or (action == "下车" and C.WARNING or C.BLUE),
        align = airui.TEXT_ALIGN_LEFT
    })
end

-- ==================== 重置信息面板为等待状态 ====================
local function reset_info_panel()
    if not student_info_container then
        return
    end

    -- 销毁旧的标签
    for _, label in ipairs(current_info_labels) do
        pcall(function()
            label:destroy()
        end)
    end
    current_info_labels = {}

    -- 显示等待提示
    local wait_label = airui.label({
        parent = student_info_container,
        text = "请将校园卡靠近感应区",
        x = 80,
        y = 70,
        w = 210,
        h = 50,
        font_size = 16,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    table.insert(current_info_labels, wait_label)
end

-- ==================== 核心刷卡逻辑 ====================
local function show_card_animation()
    if card_area then
        card_area:set_color(0xF0F6FF)
        sys.timerStart(function()
            if card_area then
                card_area:set_color(0xE9F0FA)
            end
        end, 300)
    end
end

local function process_card_swipe(card_uid, action_type)
    local student = card_to_student_map[card_uid]
    local is_unknown = false
    local is_special = false
    
    if not student then
        is_unknown = true
        is_special = true
        student = {
            id = "UNKNOWN",
            name = "未注册卡片",
            grade = "待登记IC卡",
            guardian = "请老师协助绑定",
            cardUid = card_uid,
            is_special = true
        }
    elseif student.is_special then
        is_special = true
    end
    
    -- 添加记录（未知卡片也记录但标记为未知）
    if not is_unknown then
        add_record(student, action_type)
    else
        local unknown_record = {
            student_name = "未知卡片",
            student_id = "----",
            action = action_type,
            time_str = get_full_time(),
            timestamp = os.time(),
            cardUid = card_uid
        }
        table.insert(ride_records, 1, unknown_record)
        while #ride_records > 20 do
            table.remove(ride_records)
        end
        save_records()
        refresh_record_list()
    end
    
    -- 更新方向标签（带图片）
    update_direction_badge(action_type)
    
    -- 更新信息面板
    refresh_info_panel(student, action_type, is_unknown, is_special)
    
    -- 显示动画和状态
    show_card_animation()
    
    local status_msg = ""
    if not is_unknown and not student.is_special then
        status_msg = action_type .. "成功" .. student.name
    elseif student.is_special and not is_unknown then
        status_msg = action_type .. "成功" .. student.name
    else
        status_msg = "未识别卡片 UID:" .. string.sub(card_uid, -4)
    end
    
    if card_status_label then
        card_status_label:set_text(status_msg)
        sys.timerStart(function()
            if card_status_label then
                card_status_label:set_text("等待刷卡")
            end
        end, 2200)
    end
    
    show_toast(status_msg, is_unknown)
end

-- ==================== 模拟刷卡 ====================
local function simulate_random_card(action)
    local rand = math.random()
    
    -- 10% 概率未知卡
    if rand < 0.1 then
        local fake_uid = "UNK_" .. math.random(1000, 9999)
        process_card_swipe(fake_uid, action)
    else
        -- 90% 概率从所有卡片中随机（包含体验卡）
        local all_cards = {}
        for uid, student in pairs(card_to_student_map) do
            table.insert(all_cards, { uid = uid, student = student })
        end
        local random_index = math.random(1, #all_cards)
        local selected = all_cards[random_index]
        process_card_swipe(selected.uid, action)
    end
end

-- ==================== 清空所有记录 ====================
local function clear_all_records()
    ride_records = {}
    save_records()
    refresh_record_list()
    
    -- 重置信息面板
    reset_info_panel()
    
    -- 重置方向标签（不带图片的原始状态）
    if direction_badge then
        pcall(function()
            direction_badge:destroy()
        end)
    end
    direction_badge = airui.label({
        parent = info_panel_bg,
        x = SCREEN_W - 180,
        y = 13,
        w = 80,
        h = 20,
        text = "上下车",
        font_size = 12,
        color = C.BLUE,
        align = airui.TEXT_ALIGN_CENTER,
        radius = 60,
        bg_color = 0xEEF2FF,
        pad = 4
    })
    
    if card_status_label then
        card_status_label:set_text("等待刷卡")
    end
    
    show_toast("已清空所有记录")
end

-- ==================== UI构建 ====================
local function create_ui()
    root_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.BG_MAIN
    })
    
    if not root_container then
        log.error("ui", "创建根容器失败")
        return
    end
    
    -- 加载历史记录
    init_fskv()
    load_records()
    
    -- ==================== 屏幕区域 ====================
    local screen_area = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.BG_MAIN
    })
    
    -- ==================== 状态栏 ====================
    local status_bar = airui.container({
        parent = screen_area,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 56,
        color = C.BG_MAIN
    })
    
    -- 设备名称
    local device_badge = airui.container({
        parent = status_bar,
        x = 24,
        y = 12,
        w = 80,
        h = 32,
        color = C.PRIMARY,
        radius = 40
    })
    airui.label({
        parent = device_badge,
        x = 0,
        y = 6,
        w = 80,
        h = 20,
        text = "校车通",
        font_size = 11,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 时间显示
    time_label = airui.label({
        parent = status_bar,
        x = SCREEN_W - 100,
        y = 16,
        w = 80,
        h = 24,
        text = get_time(),
        font_size = 14,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    local timer_clock = sys.timerLoopStart(function()
        if time_label then
            time_label:set_text(get_time())
        end
    end, 1000)
    add_timer(timer_clock)
    
    -- ==================== 刷卡区域 ====================
    card_area = airui.container({
        parent = screen_area,
        x = 24,
        y = 70,
        w = SCREEN_W - 48,
        h = 140,
        color = 0xE9F0FA,
        radius = 32,
        border_width = 1,
        border_color = 0x4878B8,
        border_opa = 64
    })
    
    -- card.png 图片图标
    airui.image({
        parent = card_area,
        src = "/luadb/card.png",
        x = 120,
        y = 30,
        w = 50,
        h = 50,
        zoom = 256,
        opacity = 255
    })
    
    card_status_label = airui.label({
        parent = card_area,
        x = 160,
        y = 50,
        w = 200,
        h = 25,
        text = "等待刷卡",
        font_size = 16,
        color = 0x2C5A8C,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 提示文字
    airui.label({
        parent = card_area,
        x = 80,
        y = 100,
        w = 250,
        h = 20,
        text = "靠近感应区  |  校园卡 / 二维码",
        font_size = 12,
        color = 0x5F7D9C,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- ==================== 信息面板 ====================
    info_panel_bg = airui.container({
        parent = screen_area,
        x = 24,
        y = 228,
        w = SCREEN_W - 48,
        h = 220,
        color = C.BG_CARD,
        radius = 28,
        border_left_width = 5,
        border_left_color = C.BLUE
    })
    
    -- 标题行
    local title_row = airui.container({
        parent = info_panel_bg,
        x = 20,
        y = 10,
        w = SCREEN_W - 88,
        h = 25,
        color = C.BG_CARD
    })
    
    -- 今日乘车记录标题前添加 clipboard_20x20.png 图片
    airui.image({
        parent = title_row,
        src = "/luadb/clipboard_20x20.png",
        x = 0,
        y = 2,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = title_row,
        x = 25,
        y = 3,
        w = 90,
        h = 20,
        text = "当前乘车信息",
        font_size = 14,
        color = 0x4A5B7A
    })
    
    -- 方向标签（初始状态）
    direction_badge = airui.label({
        parent = title_row,
        x = SCREEN_W - 180,
        y = 3,
        w = 80,
        h = 20,
        text = "上下车",
        font_size = 12,
        color = C.BLUE,
        align = airui.TEXT_ALIGN_CENTER,
        radius = 60,
        bg_color = 0xEEF2FF,
        pad = 4
    })
    
    -- 学生信息内容容器
    student_info_container = airui.container({
        parent = info_panel_bg,
        x = 20,
        y = 40,
        w = SCREEN_W - 88,
        h = 170,
        color = C.BG_CARD
    })
    
    -- 默认等待提示
    reset_info_panel()
    
    -- ==================== 乘车记录区域 ====================
    local record_section = airui.container({
        parent = screen_area,
        x = 24,
        y = 466,
        w = SCREEN_W - 48,
        h = 220,
        color = 0xffffff,
        radius = 24
    })
    
    -- 记录标题
    local record_title = airui.container({
        parent = record_section,
        x = 15,
        y = 5,
        w = 400,
        h = 30,
        color = 0xffffff
    }) 
    
    -- 今日乘车记录标题前添加 clipboard_20x20.png 图片
    airui.image({
        parent = record_title,
        src = "/luadb/clipboard_20x20.png",
        x = 0,
        y = 5,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = record_title,
        x = 25,
        y = 5,
        w = 90,
        h = 20,
        text = "今日乘车记录",
        font_size = 14,
        color = 0x3F5579
    })
    
    airui.label({
        parent = record_title,
        x = 310,
        y = 5,
        w = 80,
        h = 20,
        text = "最近5条",
        font_size = 11,
        color = C.TEXT_LIGHT,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 记录列表容器
    record_list_area = airui.container({
        parent = record_section,
        x = 0,
        y = 38,
        w = 430,
        h = 170,
        color = 0xffffff,
        radius = 24,
    })
    
    refresh_record_list()
    
    -- ==================== 底部按钮区域 ====================
    local bottom_btn_area = airui.container({
        parent = screen_area,
        x = 24,
        y = SCREEN_H - 80,
        w = SCREEN_W - 48,
        h = 60,
        color = C.BG_MAIN
    })
    
    -- 上车按钮（带 bus_front_20x20.png 图片）
    local up_btn_container = airui.container({
        parent = bottom_btn_area,
        x = 0,
        y = 0,
        w = 110,
        h = 50,
        color = C.INFO,
        radius = 30,
        on_click = function()
            simulate_random_card("上车")
        end
    })
    
    airui.image({
        parent = up_btn_container,
        src = "/luadb/bus_front_20x20.png",
        x = 15,
        y = 15,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = up_btn_container,
        x = 40,
        y = 15,
        w = 50,
        h = 20,
        text = "上车",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 下车按钮（带 school_20x20.png 图片）
    local down_btn_container = airui.container({
        parent = bottom_btn_area,
        x = 130,
        y = 0,
        w = 110,
        h = 50,
        color = C.WARNING,
        radius = 30,
        on_click = function()
            simulate_random_card("下车")
        end
    })
    
    airui.image({
        parent = down_btn_container,
        src = "/luadb/school_20x20.png",
        x = 15,
        y = 15,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = down_btn_container,
        x = 40,
        y = 15,
        w = 50,
        h = 20,
        text = "下车",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 清空记录按钮（带 trash_20x20.png 图片）
    local clear_btn_container = airui.container({
        parent = bottom_btn_area,
        x = SCREEN_W - 48 - 110,
        y = 0,
        w = 110,
        h = 50,
        color = C.INACTIVE_BG,
        radius = 30,
        border_width = 1,
        border_color = C.BORDER,
        on_click = function()
            clear_all_records()
        end
    })
    
    airui.image({
        parent = clear_btn_container,
        src = "/luadb/trash_20x20.png",
        x = 15,
        y = 15,
        w = 20,
        h = 20,
        zoom = 256,
        opacity = 255
    })
    
    airui.label({
        parent = clear_btn_container,
        x = 40,
        y = 15,
        w = 50,
        h = 20,
        text = "清空",
        font_size = 14,
        color = C.TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    log.info("ui", "智慧校车刷卡系统UI创建完成")
end

-- ==================== 窗口生命周期 ====================
local function on_create()
    log.info("win", "校车系统窗口创建")
    create_ui()
end

local function on_destroy()
    log.info("win", "校车系统窗口销毁，停止所有定时器")
    stop_all_timers()
    
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if current_toast then
        pcall(function()
            current_toast:destroy()
        end)
        current_toast = nil
    end
    
    if root_container then
        pcall(function()
            root_container:destroy()
        end)
        root_container = nil
    end
    
    -- 清空引用
    card_area = nil
    card_status_label = nil
    info_panel_bg = nil
    student_info_container = nil
    direction_badge = nil
    record_list_area = nil
    time_label = nil
    record_items = {}
    current_info_labels = {}
    
    win_id = nil
    collectgarbage("collect")
end

local function on_get_focus()
    log.info("win", "校车系统窗口获得焦点")
    if time_label then
        time_label:set_text(get_time())
    end
    refresh_record_list()
end

local function on_lose_focus()
    log.info("win", "校车系统窗口失去焦点")
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_SCHOOL_BUS_WIN", open_handler)

return school_bus_win