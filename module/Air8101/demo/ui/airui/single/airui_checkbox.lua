--[[
@module checkbox_page
@summary 复选框组件演示
@version 1.0
@date 2026.05.20
@author 江访
@usage
本文件演示airui.checkbox组件的用法，包括创建、状态切换、样式设置和销毁。
]]

local function ui_main()
    -- ========== 基础 Checkbox ==========
    local cb1 = airui.checkbox({
        x = 20, y = 20, w = 300, h = 40,
        text = "基础选项 (默认)",
        on_change = function(self)
            log.info("cb1", "state changed ->", self:get_checked())
        end
    })
    log.info("airui", "cb1 created", cb1 ~= nil)

    -- ========== 默认勾选的 Checkbox ==========
    local cb2 = airui.checkbox({
        x = 20, y = 60, w = 300, h = 40,
        text = "默认勾选",
        checked = true,
        on_change = function(self)
            log.info("cb2", "state changed ->", self:get_checked())
        end
    })
    log.info("airui", "cb2 created", cb2 ~= nil)

    -- ========== 自定义 style 表 (文字颜色) ==========
    local cb3 = airui.checkbox({
        x = 20, y = 100, w = 300, h = 40,
        text = "自定义文字颜色",
        checked = true,
        style = {
            text_color = 0x174EA6,
            checked_text_color = 0xD93025,
            text_font_size = 32,
        },
        on_change = function(self)
            log.info("cb3", "state changed ->", self:get_checked())
        end
    })
    log.info("airui", "cb3 created", cb3 ~= nil)

    -- ========== 另一个自定义样式 ==========
    local cb4 = airui.checkbox({
        x = 20, y = 140, w = 300, h = 40,
        text = "另一个文字颜色",
        checked = false,
        style = {
            text_color = 0x188038,
            checked_text_color = 0x188038,
        },
        on_change = function(self)
            log.info("cb4", "state changed ->", self:get_checked())
        end
    })
    log.info("airui", "cb4 created", cb4 ~= nil)

    -- ========== 测试 API 方法 ==========
    -- 测试 set_text / get_text
    local old_text = cb1:get_text()
    log.info("cb1", "old text ->", old_text)
    cb1:set_text("已改文本")
    local new_text = cb1:get_text()
    log.info("cb1", "new text ->", new_text)

    -- 3秒后测试 set_checked / get_checked
    sys.timerLoopStart(function()
        cb2:set_checked(not cb2:get_checked())
        log.info("cb2", "toggle ->", cb2:get_checked())
    end, 3000)

    -- 5秒后测试 set_on_change / set_style
    sys.timerStart(function()
        cb3:set_style({
            text_color = 0xD93025,
            checked_text_color = 0x1A73E8,
        })
        log.info("cb3", "style updated")
    end, 5000)

    -- 8秒后销毁 cb4
    sys.timerStart(function()
        local text = cb4:get_text()
        log.info("cb4", "before destroy ->", text, "checked", cb4:get_checked())
        cb4:destroy()
        sys.wait(100)
        if cb4:is_destroyed() then
            log.info("cb4", "destroyed ok")
        else
            log.info("cb4", "destroy failed")
        end
    end, 8000)
end

sys.taskInit(ui_main)
