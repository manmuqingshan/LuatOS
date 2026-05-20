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
    -- 创建表格
    local tbl = airui.table({
        x = 0, y = 0, w = 480, h = 250,
        rows = 5,
        cols = 3,
        col_width = {80, 180, 180},
        data = {
            {"ID", "Name", "状态"},
            {"001", "通讯模块", "待机"},
            {"002", "传感器", "故障"},
            {"003", "执行器", "正常"},
            {"004", "电源", "正常"},
        },
        style = {
            border_width = 0,
            cell_font_size = 12,
            cell_border_width = 0,
            cell_text_align = airui.TEXT_ALIGN_LEFT,
        },
        on_click = function(self, row, col, value)
            log.info("table", "clicked cell", self, row, col, value)
        end
    })

    -- 合并单元格按钮
    airui.button({
        x = 20, y = 300, w = 100, h = 40,
        text = "合并",
        on_click = function()
            tbl:merge_cells(1, 1, 2)
            log.info("table", "merged cells at row 1, col 1, count 2")
        end
    })

    -- 取消合并按钮
    airui.button({
        x = 140, y = 300, w = 100, h = 40,
        text = "取消合并",
        on_click = function()
            tbl:unmerge_cells(1, 1, 2)
            log.info("table", "unmerged cells at row 1, col 1, count 2")
        end
    })
end

sys.taskInit(ui_main)
