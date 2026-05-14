--[[
@module  player_win
@summary MJPG视频播放器窗口模块
@version 1.1.0
@date    2026.04.10
@author  拓毅恒
@usage
实现MJPG视频播放器功能，包括：
1. 文件选择页面 - 浏览并选择MJPG文件
2. 播放控制页面 - 播放/暂停、进度拖动、帧率设置

API使用基于 airui.video 组件：
- airui.video(config) - 创建视频组件
- video:play() - 开始播放
- video:pause() - 暂停播放
- video:stop() - 停止播放
- video:destroy() - 销毁视频组件
]]

local win_id = nil
local main_container = nil

-- 页面状态
local current_page = "home"  -- "home" 或 "player"

-- 视频组件对象
local video_component = nil
local is_playing = false
local current_fps = 15
local selected_file_path = nil

-- UI组件引用
local home_page_container = nil
local player_page_container = nil
local file_name_label = nil
local play_btn = nil
local frame_slider = nil
local current_frame_label = nil
local frame_total_badge = nil
local play_pause_btn_label = nil
local file_info_label = nil
local fps_select_label = nil
local storage_btn = nil
local storage_btn_label = nil
local file_dropdown = nil
local download_btn = nil  -- 下载按钮
local download_btn_label = nil  -- 下载按钮文字标签
local download_progress_label = nil  -- 下载进度文本标签

-- 存储位置状态
local current_storage = "memory"  -- "memory" / "sd" / "server"
-- 内存文件路径
local current_directory = "/luadb/res/"

-- 服务器视频URL
local SERVER_VIDEO_URL = "https://d3-nfs.oss-cn-shanghai.aliyuncs.com/iot-apps/res/100197/video_160x160.mjpg"
local DOWNLOADED_FILE_PATH = "/ram/server_video.mjpg"

-- 清理下载的视频文件
local function cleanup_downloaded_video()
    -- 检查文件是否存在
    local f = io.open(DOWNLOADED_FILE_PATH, "rb")
    if f then
        f:close()
        -- 删除文件
        os.remove(DOWNLOADED_FILE_PATH)
        log.info("videoplayer", "已删除下载的视频文件:", DOWNLOADED_FILE_PATH)
    end
end

-- SD卡挂载状态
local sd_mounted = false

-- 检查SD卡是否挂载
local function check_sd_mounted()
    local mounts = io.lsmount()
    if mounts then
        for _, mount in ipairs(mounts) do
            if mount == "/sd" then
                return true
            end
        end
    end
    return false
end

-- 颜色配置
local COLORS = {
    -- 主色调
    primary_dark = 0x1F2A44,      -- 深色主色
    primary_darker = 0x131C2E,    -- 更深色
    
    -- 文字颜色
    text_primary = 0x1E2A44,      -- 主文字
    text_secondary = 0x8E9AAF,    -- 次要文字
    text_aux = 0x4B5B7A,          -- 辅助文字
    
    -- 背景颜色
    white = 0xFFFFFF,             -- 纯白背景
    bg_card = 0xF8FAFE,           -- 卡片背景
    bg_light = 0xF1F5F9,          -- 浅色背景
    border = 0xEFF3F9,            -- 边框色
    
    -- 控件颜色
    button_bg = 0xEFF3FC,         -- 按钮背景
    button_border = 0xE2E8F2,     -- 按钮边框
    control_bg = 0xF8FAFE,        -- 控制区背景
}

-- FPS选项
local FPS_OPTIONS = {10, 15, 24, 30}
local fps_option_index = 2  -- 默认15fps

-- 扫描指定目录的MJPG文件
local function scan_mjpg_files(directory)
    local files = {}
    directory = directory or "/"
    -- 确保路径以 / 结尾
    if not directory:match("/$") then
        directory = directory .. "/"
    end
    -- 使用 io.lsdir 列出目录内容
    local ret, data = io.lsdir(directory, 50, 0)
    if ret and data then
        for _, entry in ipairs(data) do
            local name = entry.name
            if name then
                -- 检查是否是文件 (type == 0 表示文件)
                if entry.type == 0 then
                    if name:match("%.[mM][jJ][pP][gG]$") or name:match("%.[mM][jJ][pP][eE][gG]$") then
                        table.insert(files, directory .. name)
                    end
                end
            end
        end
    end
    return files
end

-- 下拉框位置配置
local DROPDOWN_Y = 250

-- 当前文件列表（用于下拉框回调）
local current_files = {}

-- 下载状态标志
local is_downloading = false

-- 启动下载任务
local function download_video_from_server()
    -- 防止重复下载
    if is_downloading then
        log.warn("videoplayer", "下载任务正在进行中，请勿重复点击")
        return
    end
    is_downloading = true
    
    sys.taskInit(function()
        log.info("videoplayer", "开始从服务器下载视频...")
        
        -- 显示下载中状态
        if download_btn then
            download_btn:set_color(0x999999)
        end
        if download_btn_label then
            download_btn_label:set_text("正在下载视频...")
        end
        if download_progress_label then
            download_progress_label:set_text("准备下载...")
        end
        
        -- 使用http下载到文件
        local total_size = 0
        local downloaded_size = 0
        local download_success = false
        
        -- 下载进度回调函数
        local function download_callback(content_len, body_len, userdata)
            if content_len and content_len > 0 then
                total_size = content_len
            end
            if body_len then
                downloaded_size = body_len
            end
            -- 更新进度显示
            if download_progress_label and total_size > 0 then
                local progress_text = string.format("下载中: %d/%d KB (%d%%)", 
                    math.floor(downloaded_size / 1024), 
                    math.floor(total_size / 1024),
                    math.floor(downloaded_size * 100 / total_size))
                download_progress_label:set_text(progress_text)
            elseif download_progress_label then
                download_progress_label:set_text(string.format("已下载: %d KB", math.floor(downloaded_size / 1024)))
            end
        end
        
        local code, headers, body_size = http.request("GET", SERVER_VIDEO_URL, nil, nil, 
            {timeout=30000, dst=DOWNLOADED_FILE_PATH, callback=download_callback}).wait(35000)
        
        if code == 200 and body_size then
            log.info("videoplayer", "视频下载成功，大小:", body_size, "保存到:", DOWNLOADED_FILE_PATH)
            if download_progress_label then
                download_progress_label:set_text(string.format("下载完成: %d KB", math.floor(body_size / 1024)))
            end
            
            -- 发布事件通知下载完成
            sys.publish("VIDEO_DOWNLOADED", DOWNLOADED_FILE_PATH, body_size)
            is_downloading = false
            return
        else
            log.error("videoplayer", "下载失败，code:", code, "body_size:", body_size)
            if download_progress_label then
                download_progress_label:set_text("下载失败")
            end
        end
        
        -- 下载失败，清理可能残留的文件
        cleanup_downloaded_video()
        
        -- 恢复按钮状态并显示失败提示
        if download_btn then
            download_btn:set_color(COLORS.primary_dark)
        end
        if download_btn_label then
            download_btn_label:set_text("下载失败，请点击重试")
        end
        
        -- 重置下载标志
        is_downloading = false
    end)
end

-- 更新文件下拉框
local function update_file_dropdown()
    -- 服务器模式下：隐藏下拉框和原播放按钮，在播放按钮位置显示"获取MJPG文件"按钮
    if current_storage == "server" then
        -- 隐藏下拉框
        if file_dropdown then
            file_dropdown:destroy()
            file_dropdown = nil
        end
        
        -- 隐藏原来的播放按钮
        if play_btn then
            play_btn:destroy()
            play_btn = nil
        end
        
        -- 创建下载按钮
        if download_btn then
            download_btn:destroy()
            download_btn = nil
            download_btn_label = nil
        end
        
        download_btn = airui.container({
            parent = home_page_container,
            x = 24, y = 600, w = 432, h = 56,
            color = COLORS.primary_dark,
            radius = 28,
            on_click = function()
                download_video_from_server()
            end
        })
        
        download_btn_label = airui.label({
            parent = download_btn,
            x = 0, y = 18, w = 432, h = 20,
            text = "获取MJPG文件",
            font_size = 20,
            color = COLORS.white,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 创建下载进度文本标签（初始隐藏）
        if download_progress_label then
            download_progress_label:destroy()
        end
        download_progress_label = airui.label({
            parent = home_page_container,
            x = 24, y = 660, w = 432, h = 30,
            text = " ",
            font_size = 16,
            color = COLORS.text_secondary,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        return
    end
    
    -- 非服务器模式下，隐藏下载按钮，恢复播放按钮
    if download_btn then
        download_btn:destroy()
        download_btn = nil
    end
    
    -- 如果播放按钮不存在，重新创建
    if not play_btn then
        play_btn = airui.container({
            parent = home_page_container,
            x = 24, y = 600, w = 432, h = 56,
            color = 0xCCCCCC,  -- 初始灰色，未选择文件时不可用
            radius = 28,
            on_click = function()
                if not selected_file_path then
                    log.warn("videoplayer", "请先选择视频文件")
                    return
                end
                
                -- 发布事件打开视频
                sys.publish("OPEN_VIDEO_FILE", selected_file_path)
            end
        })
        
        airui.label({
            parent = play_btn,
            x = 0, y = 18, w = 432, h = 20,
            text = "播放影片",
            font_size = 20,
            color = COLORS.white,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    log.info("videoplayer", "开始扫描目录:", current_directory)
    current_files = scan_mjpg_files(current_directory)
    log.info("videoplayer", "扫描完成，文件数:", #current_files)
    for i, f in ipairs(current_files) do
        log.info("videoplayer", "扫描到文件[" .. i .. "]:", f)
    end
    local options = {}
    
    for _, file_path in ipairs(current_files) do
        local file_name = file_path:match("[^/]+$") or file_path
        table.insert(options, file_name)
    end
    
    if #options == 0 then
        table.insert(options, "无视频文件")
    end
    
    -- 扫描到文件后，自动选择第一个文件并启用播放按钮
    if #current_files > 0 then
        selected_file_path = current_files[1]
        if play_btn then
            play_btn:set_color(COLORS.primary_dark)
        end
        log.info("videoplayer", "自动选择第一个文件:", selected_file_path)
    end
    
    -- 重新创建下拉框
    if file_dropdown then
        file_dropdown:destroy()
    end
    
    file_dropdown = airui.dropdown({
        parent = home_page_container,
        x = 24, y = DROPDOWN_Y, w = 432, h = 50,
        options = options,
        default_index = 0,
        on_change = function(self, idx, value)
            if value ~= "无视频文件" then
                selected_file_path = current_files[idx + 1]
                if play_btn then
                    play_btn:set_color(COLORS.primary_dark)
                end
                log.info("videoplayer", "选择文件", selected_file_path)
            end
        end
    })
end

-- 切换存储位置
local function toggle_storage()
    if current_storage == "memory" then
    --     -- 切换到SD卡前检查是否挂载
    --     if not check_sd_mounted() then
    --         log.warn("videoplayer", "SD卡未挂载")
    --         -- return
    --     end
    --     current_storage = "sd"
    --     current_directory = "/sd/"
    --     if storage_btn_label then
    --         storage_btn_label:set_text("SD卡")
    --     end
    -- elseif current_storage == "sd" then
        -- 切换到服务器模式
        current_storage = "server"
        current_directory = nil
        if storage_btn_label then
            storage_btn_label:set_text("服务器")
        end
    else
        -- 切换回内存
        current_storage = "memory"
        current_directory = "/luadb/res/"
        if storage_btn_label then
            storage_btn_label:set_text("内存")
        end
    end
    update_file_dropdown()
    -- 列出当前目录所有文件
    if current_directory then
        local files = scan_mjpg_files(current_directory)
        log.info("videoplayer", "切换到", current_storage, current_directory, "文件数:", #files)
        for i, file in ipairs(files) do
            log.info("videoplayer", "文件[" .. i .. "]", file)
        end
    else
        log.info("videoplayer", "切换到", current_storage, "服务器模式")
    end
end

-- 格式化文件大小
local function format_file_size(size)
    if size < 1024 then
        return size .. " B"
    elseif size < 1024 * 1024 then
        return string.format("%.1f KB", size / 1024)
    else
        return string.format("%.1f MB", size / 1024 / 1024)
    end
end

-- 获取文件大小
local function get_file_size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size
end

-- 开始/暂停播放
local function toggle_play()
    if not video_component then
        log.warn("videoplayer", "没有创建视频组件")
        return
    end
    
    is_playing = not is_playing
    if is_playing then
        video_component:play()
        if play_pause_btn_label then
            play_pause_btn_label:set_text("暂停")
        end
    else
        video_component:pause()
        if play_pause_btn_label then
            play_pause_btn_label:set_text("播放")
        end
    end
end

-- 停止播放
local function stop_play()
    if video_component then
        video_component:stop()
    end
    is_playing = false
    if play_pause_btn_label then
        play_pause_btn_label:set_text("播放")
    end
end

-- 视频容器
local video_container = nil

-- 最大容器尺寸
local MAX_CONTAINER_WIDTH = 400
local MAX_CONTAINER_HEIGHT = 300

-- 打开视频文件
local function open_video_file(file_path)
    -- 销毁之前的视频组件和容器
    if video_component then
        video_component:destroy()
        video_component = nil
    end
    if video_container then
        video_container:destroy()
        video_container = nil
    end
    
    log.info("videoplayer", "创建视频组件:", file_path)
    
    -- videoplayer模块在沙箱外执行，需要将文件复制到/ram/目录
    -- 先通过io读取文件内容，然后写入/ram/临时文件
    local temp_ram_path = "/ram/temp_video.mjpg"
    local actual_path = temp_ram_path
    
    -- 读取原文件内容
    local src_file = io.open(file_path, "rb")
    if src_file then
        local content = src_file:read("*a")
        src_file:close()
        
        if content and #content > 0 then
            -- 写入到/ram/临时文件
            local dst_file = io.open(temp_ram_path, "wb")
            if dst_file then
                dst_file:write(content)
                dst_file:close()
                log.info("videoplayer", "文件已复制到:", temp_ram_path, "大小:", #content)
                actual_path = temp_ram_path
            else
                log.error("videoplayer", "无法创建临时文件:", temp_ram_path)
            end
        else
            log.error("videoplayer", "读取文件内容为空:", file_path)
        end
    else
        log.error("videoplayer", "无法打开文件:", file_path)
    end
    
    -- AirUI适配参数
    -- 根据 rtos.bsp() 判断是真机还是模拟器
    local bsp = rtos.bsp()
    local scale_x, scale_y
    if bsp == "PC" then
        -- 模拟器
        scale_x = 1.0
        scale_y = 854 / 800  -- 1.0675
    else
        -- 真机
        scale_x = 320 / 480  -- 0.6667
        scale_y = 480 / 800  -- 0.6
    end
    log.info("videoplayer", "设备类型:", bsp, "缩放比例:", scale_x, scale_y)
    
    -- 使用/ram/路径打开视频获取实际分辨率
    local temp_player, err = videoplayer.open(actual_path)
    local video_width, video_height = 160, 160  -- 默认值
    if temp_player then
        local info = videoplayer.info(temp_player)
        if info then
            video_width = info.width
            video_height = info.height
            log.info("videoplayer", "视频实际分辨率:", video_width, "x", video_height)
        end
        videoplayer.close(temp_player)
    else
        log.warn("videoplayer", "无法获取视频信息，使用默认尺寸:", err)
    end
    
    -- 计算容器大小（补偿AirUI适配缩放）
    -- 容器设计尺寸 = 视频实际尺寸 / 缩放比例
    local container_width = math.floor(video_width / scale_x + 0.5)
    local container_height = math.floor(video_height / scale_y + 0.5)
    
    -- 限制最大尺寸
    if container_width > MAX_CONTAINER_WIDTH then
        container_width = MAX_CONTAINER_WIDTH
    end
    if container_height > MAX_CONTAINER_HEIGHT then
        container_height = MAX_CONTAINER_HEIGHT
    end
    
    log.info("videoplayer", "容器设计尺寸:", container_width, "x", container_height, 
             "实际显示约:", math.floor(container_width * scale_x), "x", math.floor(container_height * scale_y))
    
    -- 计算居中位置
    local screen_width = 480
    local container_x = math.floor((screen_width - container_width) / 2)
    local container_y = 140
    
    -- 创建容器
    video_container = airui.container({
        parent = player_page_container,
        x = container_x, y = container_y, w = container_width, h = container_height,
        color = 0x000000,  -- 黑色背景
        clip = true,       -- 启用裁剪，超出容器的内容会被裁剪
    })
    
    -- 创建 airui.video 组件
    -- airui.video在沙箱内执行，使用虚拟路径
    -- 不设置w和h，让组件使用视频原始尺寸（airui.video不支持缩放）
    local interval = math.floor(1000 / current_fps)
    video_component = airui.video({
        parent = video_container,
        x = 0, y = 0,
        src = file_path,
        format = "mjpg",
        interval = interval,
        loop = true
    })
    
    if not video_component then
        log.error("videoplayer", "创建视频组件失败")
        return false
    end
    
    selected_file_path = file_path
    is_playing = false
    
    log.info("videoplayer", "视频组件创建成功:", container_width, "x", container_height)
    return true
end

-- 切换页面
local function switch_page(page_name)
    current_page = page_name
    if page_name == "home" then
        if home_page_container then
            home_page_container:set_hidden(false)
        end
        if player_page_container then
            player_page_container:set_hidden(true)
        end
        -- 停止播放
        stop_play()
        -- 销毁视频组件和容器
        if video_component then
            video_component:destroy()
            video_component = nil
        end
        if video_container then
            video_container:destroy()
            video_container = nil
        end
        -- 清理/ram/中的临时视频文件
        local ram_files = scan_mjpg_files("/ram")
        for _, file_path in ipairs(ram_files) do
            if file_path:match("temp_video_%d+%.mjpg$") then
                os.remove(file_path)
                log.info("videoplayer", "清理临时文件:", file_path)
            end
        end
    else
        if home_page_container then
            home_page_container:set_hidden(true)
        end
        if player_page_container then
            player_page_container:set_hidden(false)
        end
    end
end

-- 显示文件选择对话框
local function show_file_selector()
    local files = scan_mjpg_files()
    if #files == 0 then
        log.warn("videoplayer", "未找到MJPG文件")
        return
    end
    
    -- 创建文件列表弹窗
    local dialog_w, dialog_h = 400, 400
    local dialog_x, dialog_y = 40, 200
    
    local dialog = airui.container({
        parent = main_container,
        x = dialog_x, y = dialog_y, w = dialog_w, h = dialog_h,
        color = COLORS.white,
        radius = 20,
        border_color = COLORS.border,
        border_width = 1
    })
    
    -- 标题
    airui.label({
        parent = dialog,
        x = 0, y = 20, w = dialog_w, h = 40,
        text = "选择视频文件",
        font_size = 24,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 文件列表容器
    local list_y = 70
    for i, file_path in ipairs(files) do
        local file_name = file_path:match("[^/]+$") or file_path
        local file_size = get_file_size(file_path)
        
        -- 创建文件项容器，使用on_click参数
        local file_item = airui.container({
            parent = dialog,
            x = 20, y = list_y + (i - 1) * 70, w = 360, h = 60,
            color = COLORS.bg_card,
            radius = 12,
            on_click = function()
                log.info("videoplayer", "选择文件", file_path)
                selected_file_path = file_path
                if file_name_label then
                    file_name_label:set_text(file_name)
                end
                if play_btn then
                    play_btn:set_style("bg_color", COLORS.primary_dark)
                end
                dialog:destroy()
            end
        })
        
        -- 文件名
        airui.label({
            parent = file_item,
            x = 15, y = 10, w = 250, h = 20,
            text = file_name,
            font_size = 16,
            color = COLORS.text_primary
        })
        
        -- 文件大小
        airui.label({
            parent = file_item,
            x = 15, y = 32, w = 100, h = 16,
            text = format_file_size(file_size),
            font_size = 12,
            color = COLORS.text_secondary
        })
    end
    
    -- 关闭按钮
    local close_btn = airui.container({
        parent = dialog,
        x = 150, y = dialog_h - 60, w = 100, h = 40,
        color = COLORS.bg_light,
        radius = 20,
        on_click = function()
            dialog:destroy()
        end
    })
    airui.label({
        parent = close_btn,
        x = 0, y = 10, w = 100, h = 20,
        text = "取消",
        font_size = 16,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 返回主界面
local function back_to_main()
    -- 清理下载的视频文件
    cleanup_downloaded_video()
    -- 停止视频播放
    stop_play()
    if win_id then
        exwin.close(win_id)
        sys.publish("OPEN_MAIN_MENU_WIN")
    end
end

-- 创建主页
local function create_home_page()
    home_page_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 800,
        color = COLORS.white
    })
    
    -- 标题区域
    local header = airui.container({
        parent = home_page_container,
        x = 0, y = 60, w = 480, h = 100,
        color = COLORS.white
    })
    
    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 20, y = 15, w = 50, h = 40,
        color = COLORS.bg_light,
        radius = 20,
        on_click = function()
            back_to_main()
        end
    })
    
    airui.label({
        parent = back_btn,
        x = 0, y = 10, w = 50, h = 20,
        text = "<",
        font_size = 20,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 主标题
    airui.label({
        parent = header,
        x = 0, y = 20, w = 480, h = 50,
        text = "MJPG 播放器",
        font_size = 36,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 副标题
    airui.label({
        parent = header,
        x = 0, y = 70, w = 480, h = 24,
        text = "基于 AirUI Video 组件 - 支持循环播放",
        font_size = 16,
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 存储位置切换按钮
    storage_btn = airui.container({
        parent = home_page_container,
        x = 360, y = 200, w = 80, h = 36,
        color = COLORS.primary_dark,
        radius = 18,
        on_click = function()
            toggle_storage()
        end
    })
    
    storage_btn_label = airui.label({
        parent = storage_btn,
        x = 0, y = 8, w = 80, h = 20,
        text = "内存",
        font_size = 16,
        color = COLORS.white,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 文件选择下拉框
    file_dropdown = airui.dropdown({
        parent = home_page_container,
        x = 24, y = DROPDOWN_Y, w = 432, h = 50,
        options = {"无视频文件"},
        default_index = 0,
        on_change = function(self, idx, value)
            if value ~= "无视频文件" then
                local files = scan_mjpg_files(current_directory)
                selected_file_path = files[idx + 1]
                if play_btn then
                    play_btn:set_color(COLORS.primary_dark)
                end
                log.info("videoplayer", "选择文件", selected_file_path)
            end
        end
    })
    
    -- 播放按钮
    play_btn = airui.container({
        parent = home_page_container,
        x = 24, y = 600, w = 432, h = 56,
        color = 0xCCCCCC,  -- 初始灰色，未选择文件时不可用
        radius = 28,
        on_click = function()
            if not selected_file_path then
                log.warn("videoplayer", "请先选择视频文件")
                return
            end
            
            -- 先打开视频
            if not open_video_file(selected_file_path) then
                log.error("videoplayer", "视频打开失败")
                return
            end
            
            -- 更新播放页面信息
            if file_info_label then
                local file_name = selected_file_path:match("[^/]+$") or selected_file_path
                local file_size = get_file_size(selected_file_path)
                local info_text = file_name .. " | " .. format_file_size(file_size)
                file_info_label:set_text(info_text)
            end
            
            -- 切换到播放页面
            switch_page("player")
            
            -- 自动开始播放
            toggle_play()
        end
    })
    
    airui.label({
        parent = play_btn,
        x = 0, y = 18, w = 432, h = 20,
        text = "播放影片",
        font_size = 20,
        color = COLORS.white,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 提示信息
    airui.label({
        parent = home_page_container,
        x = 24, y = 680, w = 432, h = 60,
        text = "支持 Motion JPEG (.mjpg) 文件\n使用 AirUI Video 组件播放",
        font_size = 14,
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 初始化文件列表
    update_file_dropdown()
end

-- 创建播放页面
local function create_player_page()
    player_page_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 800,
        color = COLORS.white,
        hidden = true
    })
    
    -- 顶部导航栏
    local header = airui.container({
        parent = player_page_container,
        x = 0, y = 0, w = 480, h = 140,
        color = COLORS.white
    })
    
    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 20, y = 15, w = 50, h = 40,
        color = COLORS.bg_light,
        radius = 20,
        on_click = function()
            -- 停止视频播放
            stop_play()
            -- 清理下载的视频文件
            cleanup_downloaded_video()
            -- 返回主页
            switch_page("home")
            -- 重置下载按钮状态（如果在服务器模式下）
            if current_storage == "server" then
                if download_btn_label then
                    download_btn_label:set_text("获取MJPG文件")
                end
                if download_btn then
                    download_btn:set_color(COLORS.primary_dark)
                end
                if download_progress_label then
                    download_progress_label:set_text("")
                end
                is_downloading = false
            end
        end
    })
    
    airui.label({
        parent = back_btn,
        x = 0, y = 10, w = 50, h = 20,
        text = "<",
        font_size = 20,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 页面标题
    airui.label({
        parent = header,
        x = 140, y = 80, w = 200, h = 30,
        text = "MJPG 播放器",
        font_size = 22,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 控制区域
    local controls = airui.container({
        parent = player_page_container,
        x = 24, y = 460, w = 432, h = 200,
        color = COLORS.control_bg,
        radius = 24,
        border_color = COLORS.border,
        border_width = 1
    })
    
    -- 播放按钮
    local play_btn_ctrl = airui.container({
        parent = controls,
        x = 20, y = 30, w = 180, h = 60,
        color = COLORS.primary_dark,
        radius = 12,
        on_click = function()
            if not is_playing then
                toggle_play()
            end
        end
    })
    
    airui.label({
        parent = play_btn_ctrl,
        x = 0, y = 18, w = 180, h = 24,
        text = "播放",
        font_size = 20,
        color = COLORS.white,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 停止按钮
    local stop_btn_ctrl = airui.container({
        parent = controls,
        x = 232, y = 30, w = 180, h = 60,
        color = COLORS.white,
        radius = 12,
        on_click = function()
            stop_play()
        end
    })
    
    airui.label({
        parent = stop_btn_ctrl,
        x = 0, y = 18, w = 180, h = 24,
        text = "停止",
        font_size = 20,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 帧率选择区域
    local speed_row = airui.container({
        parent = controls,
        x = 20, y = 120, w = 392, h = 50,
        color = COLORS.bg_light,
        radius = 25
    })
    
    airui.label({
        parent = speed_row,
        x = 20, y = 15, w = 150, h = 20,
        text = "播放速度 (帧/秒)",
        font_size = 14,
        color = COLORS.text_aux
    })
    
    -- FPS显示
    fps_select_label = airui.label({
        parent = speed_row,
        x = 265, y = 12, w = 90, h = 26,
        text = "15 fps",
        font_size = 16,
        color = COLORS.primary_dark,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- FPS选择按钮 (左) - 使用on_click参数
    local fps_prev_btn = airui.container({
        parent = speed_row,
        x = 240, y = 10, w = 30, h = 30,
        color = COLORS.white,
        radius = 15,
        on_click = function()
            if fps_option_index > 1 then
                fps_option_index = fps_option_index - 1
                current_fps = FPS_OPTIONS[fps_option_index]
                fps_select_label:set_text(current_fps .. " fps")
                -- 更新视频播放间隔
                if video_component then
                    -- 重新创建视频组件以应用新的帧率
                    local was_playing = is_playing
                    stop_play()
                    open_video_file(selected_file_path)
                    if was_playing then
                        toggle_play()
                    end
                end
            end
        end
    })
    
    airui.label({
        parent = fps_prev_btn,
        x = 0, y = 5, w = 30, h = 20,
        text = "<",
        font_size = 16,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- FPS选择按钮 (右) - 使用on_click参数
    local fps_next_btn = airui.container({
        parent = speed_row,
        x = 340, y = 10, w = 30, h = 30,
        color = COLORS.white,
        radius = 15,
        on_click = function()
            if fps_option_index < #FPS_OPTIONS then
                fps_option_index = fps_option_index + 1
                current_fps = FPS_OPTIONS[fps_option_index]
                fps_select_label:set_text(current_fps .. " fps")
                -- 更新视频播放间隔
                if video_component then
                    -- 重新创建视频组件以应用新的帧率
                    local was_playing = is_playing
                    stop_play()
                    open_video_file(selected_file_path)
                    if was_playing then
                        toggle_play()
                    end
                end
            end
        end
    })
    
    airui.label({
        parent = fps_next_btn,
        x = 0, y = 5, w = 30, h = 20,
        text = ">",
        font_size = 16,
        color = COLORS.text_primary,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 文件信息
    file_info_label = airui.label({
        parent = player_page_container,
        x = 24, y = 750, w = 432, h = 40,
        text = " ",
        font_size = 12,
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 窗口创建回调
local function on_create()
    log.info("videoplayer", "创建窗口")
    
    -- 检查SD卡挂载状态
    sd_mounted = check_sd_mounted()
    log.info("videoplayer", "SD卡挂载状态", sd_mounted)
    
    main_container = airui.container({
        x = 0, y = 0, w = 480, h = 800,
        color = COLORS.white
    })
    
    -- 创建两个页面
    create_home_page()
    create_player_page()
    
    -- 确保显示主页，隐藏播放页
    switch_page("home")
end

-- 窗口销毁回调
local function on_destroy()
    log.info("videoplayer", "销毁窗口")
    
    -- 停止播放
    stop_play()
    
    -- 销毁视频组件
    if video_component then
        video_component:destroy()
        video_component = nil
    end
    
    -- 清理视频容器
    if video_container then
        video_container:destroy()
        video_container = nil
    end
    
    -- 清理下载的视频文件
    cleanup_downloaded_video()
    
    -- 清理/ram/中的临时视频文件
    local ram_files = scan_mjpg_files("/ram")
    for _, file_path in ipairs(ram_files) do
        if file_path:match("temp_video_%d+%.mjpg$") then
            os.remove(file_path)
            log.info("videoplayer", "清理临时文件:", file_path)
        end
    end
    
    -- 清理UI
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    win_id = nil
end

-- 订阅打开视频事件
sys.subscribe("OPEN_VIDEO_FILE", function(file_path)
    -- 先打开视频
    if not open_video_file(file_path) then
        log.error("videoplayer", "视频打开失败")
        return
    end
    
    -- 更新播放页面信息
    if file_info_label then
        local file_name = file_path:match("[^/]+$") or file_path
        local file_size = get_file_size(file_path)
        local info_text = file_name .. " | " .. format_file_size(file_size)
        file_info_label:set_text(info_text)
    end
    
    -- 切换到播放页面
    switch_page("player")
    
    -- 自动开始播放
    toggle_play()
end)

-- 订阅下载完成事件（download_video_from_server已在前面定义）
sys.subscribe("VIDEO_DOWNLOADED", function(file_path, file_size)
    -- 设置选中文件路径
    selected_file_path = file_path
    
    -- 打开视频并播放
    if open_video_file(file_path) then
        -- 更新播放页面信息
        if file_info_label then
            local file_name = "server_video.mjpg"
            local info_text = file_name .. " | " .. format_file_size(file_size)
            file_info_label:set_text(info_text)
        end
        
        -- 切换到播放页面
        switch_page("player")
        
        -- 自动开始播放
        toggle_play()
    else
        log.error("videoplayer", "视频打开失败")
        -- 打开失败，清理下载的文件
        cleanup_downloaded_video()
        -- 恢复按钮状态
        if download_btn then
            download_btn:set_color(COLORS.primary_dark)
        end
    end
end)

-- 打开窗口
sys.subscribe("OPEN_VIDEOPLAYER_WIN", function()
    if win_id then
        log.warn("videoplayer", "窗口已存在")
        return
    end
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy
    })
    
    log.info("videoplayer", "窗口ID", win_id)
end)
