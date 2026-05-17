--[[
@module  nonogram
@summary 数织游戏核心逻辑模块
@version 1.0
@date    2026.05.13
@usage
本模块为数织游戏的逻辑核心，包含：
1、随机谜题生成与唯一解验证
2、单元格状态管理
3、答案校验与错误检测
]]

local nonogram = {}

-- ========================================
-- 模块级变量
-- ========================================

-- 游戏状态
nonogram.state = {
    cells = {},        -- 玩家当前状态: 0=空, 1=填色, -1=叉号
    rowClues = {},     -- 行提示数字
    colClues = {},     -- 列提示数字
    grid = {},         -- 答案网格 (0/1)
    mode = "fill",     -- 当前模式: "fill"=填色, "cross"=打叉
    size = 0,          -- 网格尺寸
}

-- ========================================
-- 工具函数
-- ========================================

local function calcClues(row)
    local clues = {}
    local count = 0
    for i = 1, #row do
        if row[i] == 1 then
            count = count + 1
        else
            if count > 0 then
                table.insert(clues, count)
                count = 0
            end
        end
    end
    if count > 0 then table.insert(clues, count) end
    if #clues == 0 then table.insert(clues, 0) end
    return clues
end

local function transpose(grid)
    local size = #grid
    local result = {}
    for c = 1, size do
        result[c] = {}
        for r = 1, size do
            result[c][r] = grid[r][c]
        end
    end
    return result
end

--[[
生成一行/列所有可能的排列
@param clues table 数字提示
@param n number 行长
@return table 所有可能的 0/1 排列
]]
local function genLineOptions(clues, n)
    if #clues == 0 then local z = {}; for i = 1, n do z[i] = 0 end; return { z } end
    if clues[1] == 0 then
        local sub = {}
        for i = 2, #clues do table.insert(sub, clues[i]) end
        return genLineOptions(sub, n)
    end
    local total = 0
    for i = 1, #clues do total = total + clues[i] end
    local minGaps = #clues - 1
    local extra = n - total - minGaps
    if extra < 0 then return {} end
    local result = {}
    local function recurse(idx, cur)
        if idx > #clues then
            while #cur < n do table.insert(cur, 0) end
            local copy = {}
            for _, v in ipairs(cur) do table.insert(copy, v) end
            table.insert(result, copy)
            return
        end
        local block = clues[idx]
        local isLast = idx == #clues
        for e = 0, extra do
            local arr = {}
            for _, v in ipairs(cur) do table.insert(arr, v) end
            for k = 1, e do table.insert(arr, 0) end
            for k = 1, block do table.insert(arr, 1) end
            if not isLast then table.insert(arr, 0) end
            if #arr <= n then
                extra = extra - e
                recurse(idx + 1, arr)
                extra = extra + e
            end
        end
    end
    recurse(1, {})
    return result
end

--[[
逻辑求解器，通过约束传播确定唯一解
@param rowClues table 行提示
@param colClues table 列提示
@param size number 尺寸
@return table|nil 网格或 nil（无解/多解）
]]
local function solve(rowClues, colClues, size)
    local grid = {}
    for r = 1, size do
        grid[r] = {}
        for c = 1, size do
            grid[r][c] = -1
        end
    end

    local rowOpts = {}
    local colOpts = {}
    for r = 1, size do
        rowOpts[r] = genLineOptions(rowClues[r], size)
        if #rowOpts[r] == 0 then return nil end
    end
    for c = 1, size do
        colOpts[c] = genLineOptions(colClues[c], size)
        if #colOpts[c] == 0 then return nil end
    end

    local changed = true
    local iterations = 0
    while changed and iterations < 200 do
        changed = false
        iterations = iterations + 1

        -- 根据已确定的格子筛选行排列
        for r = 1, size do
            local opts = rowOpts[r]
            if #opts == 0 then return nil end
            local filtered = {}
            for oi = 1, #opts do
                local opt = opts[oi]
                local ok = true
                for c = 1, size do
                    if grid[r][c] ~= -1 and grid[r][c] ~= opt[c] then
                        ok = false
                        break
                    end
                end
                if ok then table.insert(filtered, opt) end
            end
            if #filtered == 0 then return nil end
            if #filtered ~= #opts then changed = true end
            rowOpts[r] = filtered
        end

        -- 根据已确定的格子筛选列排列
        for c = 1, size do
            local opts = colOpts[c]
            if #opts == 0 then return nil end
            local filtered = {}
            for oi = 1, #opts do
                local opt = opts[oi]
                local ok = true
                for r = 1, size do
                    if grid[r][c] ~= -1 and grid[r][c] ~= opt[r] then
                        ok = false
                        break
                    end
                end
                if ok then table.insert(filtered, opt) end
            end
            if #filtered == 0 then return nil end
            if #filtered ~= #opts then changed = true end
            colOpts[c] = filtered
        end

        -- 从行排列推断确定值
        for r = 1, size do
            local opts = rowOpts[r]
            if #opts == 1 then
                for c = 1, size do
                    if grid[r][c] ~= opts[1][c] then
                        grid[r][c] = opts[1][c]
                        changed = true
                    end
                end
            else
                for c = 1, size do
                    local val = opts[1][c]
                    local allSame = true
                    for oi = 2, #opts do
                        if opts[oi][c] ~= val then
                            allSame = false
                            break
                        end
                    end
                    if allSame and grid[r][c] ~= val then
                        grid[r][c] = val
                        changed = true
                    end
                end
            end
        end

        -- 从列排列推断确定值
        for c = 1, size do
            local opts = colOpts[c]
            if #opts == 1 then
                for r = 1, size do
                    if grid[r][c] ~= opts[1][r] then
                        grid[r][c] = opts[1][r]
                        changed = true
                    end
                end
            else
                for r = 1, size do
                    local val = opts[1][r]
                    local allSame = true
                    for oi = 2, #opts do
                        if opts[oi][r] ~= val then
                            allSame = false
                            break
                        end
                    end
                    if allSame and grid[r][c] ~= val then
                        grid[r][c] = val
                        changed = true
                    end
                end
            end
        end
    end

    -- 检查是否所有格子都已确定
    for r = 1, size do
        for c = 1, size do
            if grid[r][c] == -1 then return nil end
        end
    end

    return grid
end

--[[
比较两个网格是否相同
]]
local function gridEq(a, b)
    for r = 1, #a do
        for c = 1, #a[1] do
            if a[r][c] ~= b[r][c] then return false end
        end
    end
    return true
end

--[[
随机生成一个网格
@param size number
@return table 0/1 网格
]]
local function randGrid(size)
    local fill = 0.35 + math.random() * 0.2
    local g = {}
    for r = 1, size do
        g[r] = {}
        for c = 1, size do
            g[r][c] = math.random() < fill and 1 or 0
        end
    end
    return g
end

--[[
生成一个唯一可解的谜题
@param size number 网格尺寸
@param maxAttempts number 最大尝试次数
@return table|nil {grid, rowClues, colClues} 或 nil
]]
local function genPuzzle(size, maxAttempts)
    for a = 1, maxAttempts do
        local grid = randGrid(size)
        local rowClues = {}
        for r = 1, size do
            rowClues[r] = calcClues(grid[r])
        end
        local t = transpose(grid)
        local colClues = {}
        for c = 1, size do
            colClues[c] = calcClues(t[c])
        end
        local solved = solve(rowClues, colClues, size)
        if solved and gridEq(solved, grid) then
            return { grid = grid, rowClues = rowClues, colClues = colClues }
        end
    end
    return nil
end

-- ========================================
-- 公共函数（供 UI 模块调用）
-- ========================================

--[[
生成新谜题
@param size 网格尺寸
@return boolean 是否成功
]]
function nonogram.newPuzzle(size)
    local result = genPuzzle(size, 2000)
    if not result then return false end

    nonogram.state.grid = result.grid
    nonogram.state.rowClues = result.rowClues
    nonogram.state.colClues = result.colClues
    nonogram.state.size = size
    nonogram.state.cells = {}
    for r = 1, size do
        nonogram.state.cells[r] = {}
        for c = 1, size do
            nonogram.state.cells[r][c] = 0
        end
    end

    return true
end

--[[
切换单元格状态
@param r 行索引
@param c 列索引
]]
function nonogram.toggleCell(r, c)
    local cur = nonogram.state.cells[r][c]
    if nonogram.state.mode == "fill" then
        nonogram.state.cells[r][c] = cur == 1 and 0 or 1
    else
        nonogram.state.cells[r][c] = cur == -1 and 0 or -1
    end
end

--[[
检查答案，返回错误列表
@return table 错误列表，每项 {r, c, expected}
]]
function nonogram.check()
    local errors = {}
    local size = nonogram.state.size
    local cells = nonogram.state.cells
    local grid = nonogram.state.grid
    for r = 1, size do
        for c = 1, size do
            local expected = grid[r][c]
            local actual = cells[r][c]
            if (actual == 1) ~= (expected == 1) then
                table.insert(errors, { r = r, c = c, expected = expected })
            end
        end
    end
    return errors
end

--[[
重置所有格子
]]
function nonogram.reset()
    local size = nonogram.state.size
    if size == 0 then return end
    for r = 1, size do
        for c = 1, size do
            nonogram.state.cells[r][c] = 0
        end
    end
end

-- 导出工具函数供 UI 使用
nonogram.calcClues = calcClues

return nonogram
