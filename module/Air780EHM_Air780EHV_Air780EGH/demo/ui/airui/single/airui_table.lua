--[[
@module table_page
@summary 表格组件演示
@version 1.1
@date 2026.05.20
@author 江访
@usage
本文件演示airui.table组件的用法，展示表格功能，包括合并/取消合并单元格。
]]

local function ui_main()
    local tbl = airui.table({
        x = 5, y = 5, h = 200, w = 310,
        rows = 5,
        cols = 3,
        col_width = {60, 120, 120},
        data = {
            {"ID", "Name", "状态"},
            {"001", "通讯模块", "待机"},
            {"002", "传感器", "故障"},
            {"003", "执行器", "正常"},
            {"004", "电源", "正常"},
        },
    })

    -- 合并单元格按钮
    airui.button({
        x = 10, y = 220, w = 100, h = 36,
        text = "合并",
        on_click = function()
            tbl:merge_cells(1, 1, 2)
        end
    })

    -- 取消合并按钮
    airui.button({
        x = 120, y = 220, w = 100, h = 36,
        text = "取消合并",
        on_click = function()
            tbl:unmerge_cells(1, 1, 2)
        end
    })
end

sys.taskInit(ui_main)
