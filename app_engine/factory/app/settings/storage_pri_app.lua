--[[
@module  settings_storage_priority_app
@summary 存储优先级配置业务逻辑层
@version 1.0
@date    2026.05.13
@author  Claude (Cowork)
@usage
本模块管理 app 安装的存储优先级配置，支持读取和保存。
]]

-- 存储位置的中文标签映射
local STORAGE_LABELS = {
    sd_tf        = "外挂TF卡",
    little_flash = "外挂Flash",
    internal     = "内置文件系统",
}

-- 存储位置的描述映射
local STORAGE_DESC = {
    sd_tf        = "TF卡插入后自动挂载，速度快，容量大",
    little_flash = "板载外挂Flash芯片，固定挂载",
    internal     = "设备内置文件系统，始终可用",
}

-- 处理 config_app 返回的原始优先级数据，附上标签和描述方便 UI 展示
sys.subscribe("STORAGE_PRIORITY_VALUE", function(priority_list)
    local enriched = {}
    for i, type_key in ipairs(priority_list) do
        table.insert(enriched, {
            type_key    = type_key,
            label       = STORAGE_LABELS[type_key] or type_key,
            description = STORAGE_DESC[type_key] or "",
            rank        = i,
        })
    end
    sys.publish("STORAGE_PRIORITY_ENRICHED", enriched)
    log.info("storage_priority_app", "enriched priority list, count:", #enriched)
end)
