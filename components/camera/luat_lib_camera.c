
/*
@module  camera
@summary 摄像头
@version 1.0
@date    2022.01.11
@demo camera
@tag LUAT_USE_CAMERA
*/
#include "luat_base.h"
#include "luat_camera.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_uart.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "camera"
#include "luat_log.h"

#define MAX_DEVICE_COUNT 2
#define MAX_USB_DEVICE_COUNT 1

typedef struct luat_camera_cb {
    int scanned;
} luat_camera_cb_t;
static luat_camera_cb_t camera_cbs[MAX_DEVICE_COUNT + MAX_USB_DEVICE_COUNT];
static uint64_t camera_idp = 0;
int l_camera_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int camera_id = msg->arg1;
    if (camera_id >= LUAT_CAMERA_TYPE_USB)
    {
        camera_id = MAX_DEVICE_COUNT + camera_id - LUAT_CAMERA_TYPE_USB;
    }
#if (defined TYPE_EC718) || (defined TYPE_EC718M)
    if (camera_cbs[0].scanned)
    {
    	camera_id = 0;
    }
    else if (camera_cbs[1].scanned)
    {
    	camera_id = 1;
    }
#endif
    if (camera_cbs[camera_id].scanned) {
        lua_geti(L, LUA_REGISTRYINDEX, camera_cbs[camera_id].scanned);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, camera_id);
            if (msg->ptr)
            {
                lua_pushlstring(L, (char *)msg->ptr,msg->arg2);
            }
            else if (msg->arg2 > 1)
            {
            	lua_pushinteger(L, msg->arg2);
            }
            else
            {
            	lua_pushboolean(L, msg->arg2);
            }
            lua_call(L, 2, 0);
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
初始化摄像头
@api    camera.init(InitReg_or_cspi_id, cspi_speed, mode, is_msb, rx_bit, seq_type, is_ddr, only_y, scan_mode, w, h)
@table/integer 如果是table,则是DVP摄像头的配置见demo/camera/dvp_camera,同时忽略后续参数;如果是数字,则是camera spi总线序号
@int camera spi总线速度
@int camera spi模式,0~3
@int 字节的bit顺序是否是msb,0否1是
@int 同时接收bit数,1,2,4
@int byte序列,0~1
@int 双边沿采样配置,0不启用,其他值根据实际SOC决定
@int 只接收Y分量，0不启用，1启用，扫码必须启用，否则会失败
@int 工作模式，camera.AUTO自动,camera.SCAN扫码
@int 摄像头宽度
@int 摄像头高度
@return int/false 成功返回camera_id，失败返回false
@usage
camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像
--初始化后需要start才开始输出/扫码
camera.start(camera_id)--开始指定的camera
*/

static int l_camera_init(lua_State *L){
	int result;
    if (lua_istable(L, 1)) {
    	luat_camera_conf_t conf = {0};
    	conf.lcd_conf = luat_lcd_get_default();
        conf.stream = 1;
        lua_pushliteral(L, "zbar_scan");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.zbar_scan = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "draw_lcd");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.draw_lcd = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "i2c_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.i2c_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "i2c_addr");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.i2c_addr = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_period");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_period = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "pwm_pulse");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.pwm_pulse = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_width");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_width = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "sensor_height");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.sensor_height = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "color_bit");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.color_bit = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_reg");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_reg = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        lua_pushliteral(L, "id_value");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id_value = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "id");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.id = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "usb_port");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.usb_port = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "stream");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.stream = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "async");
        lua_gettable(L, 1);
        if (lua_isinteger(L, -1)) {
            conf.async = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_pushliteral(L, "init_cmd");
        lua_gettable(L, 1);
        if (lua_istable(L, -1)) {
            conf.init_cmd_size = lua_rawlen(L, -1);
            conf.init_cmd = luat_heap_malloc(conf.init_cmd_size * sizeof(uint8_t));
            for (size_t i = 1; i <= conf.init_cmd_size; i++){
                lua_geti(L, -1, i);
                conf.init_cmd[i-1] = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
        }else if(lua_isstring(L, -1)){
            size_t len;
            int cmd;
            const char *fail_name = luaL_checklstring(L, -1, &len);
            FILE* fd = luat_fs_fopen(fail_name, "rb");
            conf.init_cmd_size = 0;
            if (fd){
                #define INITCMD_BUFF_SIZE 128
                char init_cmd_buff[INITCMD_BUFF_SIZE] ;
                conf.init_cmd = luat_heap_malloc(sizeof(uint8_t));
                while (1) {
                    memset(init_cmd_buff, 0, INITCMD_BUFF_SIZE);
                    int readline_len = luat_fs_readline(init_cmd_buff, INITCMD_BUFF_SIZE-1, fd);
                    if (readline_len < 1)
                        break;
                    if (memcmp(init_cmd_buff, "#", 1)==0){
                        continue;
                    }
                    char *token = strtok(init_cmd_buff, ",");
                    if (sscanf(token,"%x",&cmd) < 1){
                        continue;
                    }
                    conf.init_cmd_size = conf.init_cmd_size + 1;
                    conf.init_cmd = luat_heap_realloc(conf.init_cmd,conf.init_cmd_size * sizeof(uint8_t));
                    conf.init_cmd[conf.init_cmd_size-1]=cmd;
                    while( token != NULL ) {
                        token = strtok(NULL, ",");
                        if (sscanf(token,"%x",&cmd) < 1){
                            break;
                        }
                        conf.init_cmd_size = conf.init_cmd_size + 1;
                        conf.init_cmd = luat_heap_realloc(conf.init_cmd,conf.init_cmd_size * sizeof(uint8_t));
                        conf.init_cmd[conf.init_cmd_size-1]=cmd;
                    }
                }
                conf.init_cmd[conf.init_cmd_size]= 0;
                luat_fs_fclose(fd);
            }else{
                LLOGE("init_cmd fail open error");
            }
        }
        lua_pop(L, 1);
        result = luat_camera_init(&conf);
        if (result < 0) {
            lua_pushboolean(L, 0);
        } else {
            if (conf.async) {
                camera_idp = luat_pushcwait(L);
            } else {
                lua_pushinteger(L, result);
            }
        }

    } else if (lua_isinteger(L, 1)) {
    	luat_spi_camera_t conf = {0};
    	conf.lcd_conf = luat_lcd_get_default();
    	int cspi_id = lua_tointeger(L, 1);
    	int default_value = 24000000;
    	conf.camera_speed = lua_tointegerx(L, 2, &default_value);
    	default_value = 0;
    	conf.spi_mode = lua_tointegerx(L, 3, &default_value);
    	conf.is_msb = lua_tointegerx(L, 4, &default_value);
    	conf.is_two_line_rx = lua_tointegerx(L, 5, &default_value) - 1;
    	conf.seq_type = lua_tointegerx(L, 6, &default_value);
    	result = lua_tointegerx(L, 7, &default_value);
    	memcpy(conf.plat_param, &result, 4);
    	conf.only_y = lua_tointegerx(L, 8, &default_value);
    	int mode = lua_tointegerx(L, 9, &default_value);
    	default_value = 240;
    	conf.sensor_width = lua_tointegerx(L, 10, &default_value);
    	default_value = 320;
    	conf.sensor_height = lua_tointegerx(L, 11, &default_value);
    	luat_camera_init(NULL);
    	luat_camera_work_mode(cspi_id, mode);
    	result = luat_camera_setup(cspi_id, &conf, NULL, 0);

        if (result < 0) {
        	lua_pushboolean(L, 0);
        } else {
        	lua_pushinteger(L, result);
        }
    } else {
    	lua_pushboolean(L, 0);
    }

    return 1;
}

/**
注册摄像头事件回调
@api    camera.on(id, event, func)
@int camera id, camera 0写0, camera 1写1
@string 事件名称
@function 回调方法
@return nil 无返回值
@usage
camera.on(0, "scanned", function(id, event)
--id int camera id
--event 多种类型，详见下表
    print(id, event)
end)
--[[
event可能出现的值有
  boolean型 false   摄像头没有正常工作，检查硬件和软件配置
  boolean型 true    拍照模式下拍照成功并保存完成，可以读取照片文件数据进一步处理，比如读出数据上传
  int型 原始图像大小 RAW模式下，采集完一帧图像后回调，回调值为图像数据大小，可以对传入的zbuff做进一步处理，比如读出数据上传
  string型  扫码结果 扫码模式下扫码成功一次，并且回调解码值，可以对回调值做进一步处理，比如打印到LCD上
]]
*/
static int l_camera_on(lua_State *L) {
    int camera_id = luaL_checkinteger(L, 1);
    const char* event = luaL_checkstring(L, 2);
    if (camera_id >= LUAT_CAMERA_TYPE_USB)
    {
        camera_id = MAX_DEVICE_COUNT + camera_id - LUAT_CAMERA_TYPE_USB;
    }
    if (!strcmp("scanned", event)) {
        if (camera_cbs[camera_id].scanned != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, camera_cbs[camera_id].scanned);
            camera_cbs[camera_id].scanned = 0;
        }
        if (lua_isfunction(L, 3)) {
            lua_pushvalue(L, 3);
            camera_cbs[camera_id].scanned = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}

/**
开始指定的camera
@api camera.start(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.start(0)
*/
static int l_camera_start(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_start(id) == 0 ? 1 : 0);
    return 1;
}

/**
停止指定的camera
@api camera.stop(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.stop(0)
*/
static int l_camera_stop(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_stop(id) == 0 ? 1 : 0);
    return 1;
}

/**
关闭指定的camera，释放相应的IO资源
@api camera.close(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.close(0)
*/
static int l_camera_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_camera_close(id) == 0 ? 1 : 0);
    return 1;
}

LUAT_WEAK int luat_camera_setup(int id, luat_spi_camera_t *conf, void * callback, void *param) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_capture(int id, uint8_t quality, const char *path) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_capture_config(int id, uint16_t start_x, uint16_t start_y, uint16_t new_w, uint16_t new_h) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_capture_in_ram(int id, uint8_t quality, void *buffer) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_get_raw_start(int id, int w, int h, uint8_t *data, uint32_t max_len) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_get_raw_again(int id) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_video(int id, int w, int h, uint8_t uart_id) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_preview(int id, uint8_t on_off){
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_work_mode(int id, int mode){
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK int luat_camera_config(int id, int key, int value) {
    LLOGD("not support yet");
    return -1;
}

LUAT_WEAK void luat_camera_pwdn_pin(int id, uint8_t level) {
    LLOGD("not support yet");
    return;
}

LUAT_WEAK void luat_camera_reset_pin(int id, uint8_t level) {
    LLOGD("not support yet");
    return;
}
/**
camera拍照
@api camera.capture(id, save_path, quality, x, y, w, h)
@int camera id,例如0
@string/zbuff/nil save_path,文件保存路径，空则写在上次路径里，默认是/capture.jpg，如果是zbuff，则将图片保存在buff内不写入文件系统
@int quality, jpeg压缩质量, 见下面的使用说明
@int x, 裁剪起始横坐标，从x列开始
@int y, 裁剪起始纵坐标，从y行开始
@int w, 裁剪后的宽度
@int h, 裁剪后的高度
@return boolean 成功返回true,否则返回false,真正完成后通过camera.on设置的回调函数回调接收到的长度
@usage
-- 保存到文件,质量为80
camera.capture(0, "/capture.jpg", 80)
-- 保存到内存文件系统
camera.capture(0, "/ram/123.jpg", 80)

-- 保存到zbuff,质量为80
camera.capture(0, buff, 80)

-- jpeg压缩质量,请使用 50 - 95 之间的数值
-- 为保持兼容性, 质量值1/2/3, 分别对应 90/95/99
*/
static int l_camera_capture(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int quality = luaL_optinteger(L, 3, 1);
    if (luat_camera_capture_config(id, luaL_optinteger(L, 4, 0), luaL_optinteger(L, 5, 0), luaL_optinteger(L, 6, 0), luaL_optinteger(L, 7, 0)))
    {
    	lua_pushboolean(L, 0);
    	return 1;
    }
    if (lua_isstring(L, 2)){
    	const char* save_path = luaL_checkstring(L, 2);
    	lua_pushboolean(L, !luat_camera_capture(id, quality, save_path));
    } else {
    	luat_zbuff_t *buff = luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
    	lua_pushboolean(L, !luat_camera_capture_in_ram(id, quality, buff));
    }
    return 1;
}

/**
camera输出视频流到USB
@api camera.video(id, w, h, out_path)
@int camera id,例如0
@int 宽度
@int 高度
@int 输出路径，目前只能用虚拟串口0
@return boolean 成功返回true,否则返回false
@usage
camera.video(0, 320, 240, uart.VUART_0)
*/
static int l_camera_video(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int w = luaL_optinteger(L, 2, 320);
    int h = luaL_optinteger(L, 3, 240);
    int param = luaL_optinteger(L, 4, LUAT_VUART_ID_0);
    lua_pushboolean(L, !luat_camera_video(id, w, h, param));
    return 1;
}


/**
启动camera输出原始数据到用户的zbuff缓存区，输出1fps后会停止，并通过camera.on设置的回调函数回调接收到的长度，如果需要再次输出，请调用camera.getRaw
@api camera.startRaw(id, w, h, buff)
@int camera id,例如0
@int 宽度
@int 高度
@zbuff 用于存放数据的缓存区，大小必须不小于w X h X 2 byte
@return boolean 成功返回true,否则返回false
@usage
camera.startRaw(0, 320, 240, buff)
*/
static int l_camera_start_raw(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int w = luaL_optinteger(L, 2, 320);
    int h = luaL_optinteger(L, 3, 240);
    luat_zbuff_t *buff = luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE);
    lua_pushboolean(L, !luat_camera_get_raw_start(id, w, h, buff->addr, buff->len));
    return 1;
}

/**
再次启动camera输出原始数据到用户的zbuff缓存区，输出1fps后会停止，并通过camera.on设置的回调函数回调接收到的长度，如果需要再次输出，请继续调用本API
@api camera.getRaw(id)
@int camera id,例如0
@return boolean 成功返回true,否则返回false
@usage
camera.getRaw(0)
*/
static int l_camera_get_raw(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushboolean(L, !luat_camera_get_raw_again(id));
    return 1;
}

/**
启停camera预览功能，直接输出到LCD上，只有硬件支持的SOC可以运行，启动预览前必须调用lcd.int等api初始化LCD，预览时自动选择已经初始化过的lcd。
@api camera.preview(id, onoff)
@int camera id,例如0
@boolean true开启，false停止
@return boolean 成功返回true,否则返回false
@usage
camera.preview(1, true)
*/
static int l_camera_preview(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    uint8_t onoff = lua_toboolean(L, 2);
    lua_pushboolean(L, !luat_camera_preview(id, onoff));
    return 1;
}


/**
配置摄像头参数
@api camera.config(id, key, value)
@int camera id,例如0
@int 配置项的id
@int 配置项的值
@return nil 当前无返回值
@usage
-- 本函数于 2025.3.17 新增, 当前仅Air8101可用
camera.config(0, camera.CONF_H264_QP_INIT, 16)
camera.config(0, camera.CONF_H264_QP_I_MAX, 16)
camera.config(0, camera.CONF_H264_QP_P_MAX, 8)
camera.config(0, camera.CONF_H264_IMB_BITS, 3)
camera.config(0, camera.CONF_H264_PMB_BITS, 1)
*/
static int l_camera_config(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int key = luaL_checkinteger(L, 2);
    int value = luaL_checkinteger(L, 3);
    int ret = luat_camera_config(id, key, value);
    lua_pushinteger(L, ret);
    return 1;
}

/*
对于无法用GPIO控制camera pwdn脚的平台，手动控制camera pwdn脚拉高或者拉低,2025/9/6启用
@api camera.pwdn_pin(level)
@int camera id,例如0
@int pwdn脚电平，1高电平，0低电平
@usage
-- camera pwdn脚低电平
camera.pwdn_pin(camera_id, 0)
*/
static int l_camera_set_pwdn_pin(lua_State* L) {
	luat_camera_pwdn_pin(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 0));
    return 0;
}

/*
对于无法用GPIO控制camera reset脚的平台，手动控制camera reset脚拉高或者拉低,2025/9/6启用
@api camera.reset_pin(level)
@int camera id,例如0
@int reset脚电平，1高电平，0低电平
@usage
-- camera reset脚高电平
camera.reset_pin(camera_id, 1)
*/
static int l_camera_set_reset_pin(lua_State* L) {
	luat_camera_reset_pin(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_camera[] =
{
    { "init" ,       ROREG_FUNC(l_camera_init )},
    { "start" ,      ROREG_FUNC(l_camera_start )},
	{ "preview",     ROREG_FUNC(l_camera_preview)},
    { "stop" ,       ROREG_FUNC(l_camera_stop)},
    { "capture",     ROREG_FUNC(l_camera_capture)},
	{ "video",       ROREG_FUNC(l_camera_video)},
	{ "startRaw",    ROREG_FUNC(l_camera_start_raw)},
	{ "getRaw",      ROREG_FUNC(l_camera_get_raw)},
	{ "close",		 ROREG_FUNC(l_camera_close)},
    { "on",          ROREG_FUNC(l_camera_on)},
    { "config",      ROREG_FUNC(l_camera_config)},
    { "pwdn_pin",      ROREG_FUNC(l_camera_set_pwdn_pin)},
    { "reset_pin",      ROREG_FUNC(l_camera_set_reset_pin)},
    //@const AUTO number 摄像头工作在自动模式
	{ "AUTO",        ROREG_INT(LUAT_CAMERA_MODE_AUTO)},
    //@const SCAN number 摄像头工作在扫码模式，只输出Y分量
	{ "SCAN",        ROREG_INT(LUAT_CAMERA_MODE_SCAN)},
    //@const USB number 摄像头类型，USB
    { "USB",         ROREG_INT(LUAT_CAMERA_TYPE_USB)},
    //@const DVP number 摄像头类型，DVP
    { "DVP",         ROREG_INT(LUAT_CAMERA_TYPE_DVP)},
    //@const ROTATE_0 number 摄像头预览，画面不旋转
    { "ROTATE_0",    ROREG_INT(LUAT_CAMERA_PREVIEW_ROTATE_0)},
    //@const ROTATE_90 number 摄像头预览，画面旋转90度
    { "ROTATE_90",   ROREG_INT(LUAT_CAMERA_PREVIEW_ROTATE_90)},
    //@const ROTATE_270 number 摄像头预览，画面旋转270度
    { "ROTATE_270",  ROREG_INT(LUAT_CAMERA_PREVIEW_ROTATE_270)},

    //@const CONF_H264_QP_INIT number H264编码器初始化QP值
    { "CONF_H264_QP_INIT",         ROREG_INT(LUAT_CAMERA_CONF_H264_QP_INIT)},
    //@const CONF_H264_QP_I_MAX number H264编码器I的最大QP值
    { "CONF_H264_QP_I_MAX",         ROREG_INT(LUAT_CAMERA_CONF_H264_QP_I_MAX)},
    //@const CONF_H264_QP_P_MAX number H264编码器P的最大QP值
    { "CONF_H264_QP_P_MAX",         ROREG_INT(LUAT_CAMERA_CONF_H264_QP_P_MAX)},
    //@const CONF_H264_IMB_BITS number H264编码器IMB_BITS值
    { "CONF_H264_IMB_BITS",         ROREG_INT(LUAT_CAMERA_CONF_H264_IMB_BITS)},
    //@const CONF_H264_PMB_BITS number H264编码器PMB_BITS值
    { "CONF_H264_PMB_BITS",         ROREG_INT(LUAT_CAMERA_CONF_H264_PMB_BITS)},
    //@const CONF_PREVIEW_ENABLE number 是否启动摄像头预览功能，默认开启
    { "CONF_PREVIEW_ENABLE",        ROREG_INT(LUAT_CAMERA_CONF_PREVIEW_ENABLE)},
    //@const CONF_PREVIEW_ROTATE number 摄像头预览画面的旋转角度
    { "CONF_PREVIEW_ROTATE",        ROREG_INT(LUAT_CAMERA_CONF_PREVIEW_ROTATE)},

	{ NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_camera( lua_State *L ) {
    luat_newlib2(L, reg_camera);
    return 1;
}

//------------------------------------------------------
static int32_t l_camera_callback(lua_State *L, void* ptr) {
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    if (camera_idp) {
        if (msg->arg1 < 0) {
            lua_pushinteger(L, 0);
        } else {
            lua_pushinteger(L, msg->arg1);
        }
        luat_cbcwait(L, camera_idp, 1);
        camera_idp = 0;
    }
    return 0;
}

void luat_camera_async_init_result(int result) {
    rtos_msg_t msg = {0};
    msg.handler = l_camera_callback;
    msg.arg1 = result;
    luat_msgbus_put(&msg, 0);
}
