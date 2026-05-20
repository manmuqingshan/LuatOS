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
    local cb1 = airui.checkbox({
        x = 10, y = 20, w = 280, h = 40,
        text = "基础选项 (默认)",
        on_change = function(self)
            log.info("cb1", "state changed ->", self:get_checked())
        end
    })

    local cb2 = airui.checkbox({
        x = 10, y = 60, w = 280, h = 40,
        text = "默认勾选",
        checked = true,
        on_change = function(self)
            log.info("cb2", "state changed ->", self:get_checked())
        end
    })

    local cb3 = airui.checkbox({
        x = 10, y = 100, w = 280, h = 40,
        text = "自定义文字颜色",
        checked = true,
        style = {
            text_color = 0x174EA6,
            checked_text_color = 0xD93025,
            text_font_size = 24,
        },
        on_change = function(self)
            log.info("cb3", "state changed ->", self:get_checked())
        end
    })

    local cb4 = airui.checkbox({
        x = 10, y = 140, w = 280, h = 40,
        text = "另一个颜色",
        checked = false,
        style = {
            text_color = 0x188038,
            checked_text_color = 0x188038,
        },
        on_change = function(self)
            log.info("cb4", "state changed ->", self:get_checked())
        end
    })

    -- 测试 set_text / get_text
    cb1:set_text("已改文本")
    log.info("cb1", "new text ->", cb1:get_text())
end

sys.taskInit(ui_main)
