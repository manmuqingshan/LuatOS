
/*
@module  audio
@summary 多媒体-音频
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_AUDIO_V2
*/
#include "luat_audio_request.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "audio_v2"
#include "luat_log.h"
#ifdef LUAT_USE_AUDIO_V2
#include "luat_common_api.h"
#include "luat_audio_core.h"

#include "luat_mem.h"

#ifndef LUAT_AUDIO_REQUEST_MAX
#define LUAT_AUDIO_REQUEST_MAX 10
#endif

typedef struct {
    luat_llist_head node;
    luat_audio_request_block_t request;
    uint8_t self_index;
} l_audio_request_t;

typedef struct {
    luat_llist_head request_free_list;
    luat_llist_head request_busy_list;
    l_audio_request_t request_table[LUAT_AUDIO_REQUEST_MAX];
    int cb_ref;
} l_audio_ctrl_t;
static l_audio_ctrl_t _l_audio;


static int _l_audio_handler(lua_State *L, void* ptr) {
    (void)ptr;
    luat_data_union_t u_data;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (_l_audio.cb_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, _l_audio.cb_ref);
        if (lua_isfunction(L, -1)) {
            u_data.u32 = msg->arg1;
            lua_pushinteger(L, u_data.u8[0]);
            lua_pushinteger(L, u_data.u8[1]);
            lua_pushinteger(L, msg->arg2);
            lua_call(L, 3, 0);
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

static void _l_audio_request_callback(uint32_t event, uint8_t *data, uint32_t len, struct luat_audio_request_block *request_block) {
    l_audio_request_t *l_req = (l_audio_request_t *)request_block->user_data;
    luat_data_union_t u_data;
    u_data.u8[0] = l_req->self_index;
    u_data.u8[1] = event;
    rtos_msg_t msg;
	msg.handler = _l_audio_handler;
	msg.ptr = NULL;
	msg.arg1 = u_data.u32;
	msg.arg2 = len;
	luat_msgbus_put(&msg, 0);
}

void l_audio_init(void)
{
    LUAT_INIT_LLIST_HEAD(&_l_audio.request_free_list);
    for(uint32_t i = 0; i < LUAT_AUDIO_REQUEST_MAX; i++)
    {
        _l_audio.request_table[i].self_index = i;
        luat_llist_add_tail(&_l_audio.request_table[i].node, &_l_audio.request_free_list);
    }
    LUAT_INIT_LLIST_HEAD(&_l_audio.request_busy_list);
}

/**
注册audio事件回调
@api    audio_v2.on(func)
@function 回调方法
@return nil 无返回值
@usage
audio_v2.on(function(request_index, msg, param)
    log.info(request_index, msg, param)
end)
--回调函数参数说明
---@param int 请求索引
---@param int 消息值
---@param int 附加参数，根据消息值不同，有不同的含义
*/
static int l_audio_on(lua_State *L) {
	if (_l_audio.cb_ref != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, _l_audio.cb_ref);
		_l_audio.cb_ref = 0;
	}
	if (lua_isfunction(L, 1)) {
		lua_pushvalue(L, 1);    
		_l_audio.cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}
    return 0;
}
/*
播放多个文件，播放完成后，会回调一个audio.DONE消息，可以用pause来暂停或者恢复，其他API不可用。考虑到读SD卡速度比较慢而拖累luavm进程的速度，所以尽量使用本API
@api audio_v2.play(path, err_stop, priority, driver, decoder)
@string/table 文件名，如果是table，则表示连续播放多个文件
@boolean 是否在文件解码失败后停止解码，只有在连续播放多个文件时才有用，默认true，遇到解码错误自动停止
@int 优先级，0~255，值越大，优先级越高，默认0
@int 驱动id，在不使用默认驱动时填写，绝大部分情况下都不需要填写
@int 解码器id，在需要指定解码器时填写，绝大部分情况下都不需要填写
@return boolean 成功返回true,否则返回false
@return int request_index 请求索引，用于后续操作，如暂停、恢复，回调信息判断等
@usage
audio_v2.play("xxxxxx")		--开始播放某个文件
*/
static int l_audio_play(lua_State *L) {
    size_t len = 0;
    int result = -1;
    uint8_t request_index = 0;
    const char *buf;
    uint8_t is_error_stop = 1;
    uint8_t priority = luaL_optinteger(L, 3, 0);

    if (lua_isboolean(L, 2)) {
        is_error_stop = lua_toboolean(L, 2);
    }
    size_t file_nums = 0;
    size_t path_len = 0;
    luat_audio_play_file_info_t *info = NULL;
    if (lua_istable(L, 1)) {
    	size_t len = lua_rawlen(L, 1); //返回数组的长度
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(len, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            goto DONE;
        }

        for (size_t i = 0; i < len; i++) {
            lua_rawgeti(L, 1, 1 + i);
            info[i].path = (void*)lua_tolstring(L, -1, &path_len);
            info[i].rom_data_len = 0;
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
        file_nums = len;
    } else if (LUA_TSTRING == (lua_type(L, (2)))) {
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(1, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            goto DONE;
        }
        info[0].path = (void*)lua_tolstring(L, 2, &path_len);
        info[0].rom_data_len = 0;
        file_nums = 1;
    } else {
    	goto DONE;
    }
    if (luat_llist_empty(&_l_audio.request_free_list)) {
        LLOGE("audio request free list is empty");
        goto DONE;
    }
    l_audio_request_t *l_req = (luat_audio_request_block_t *)&_l_audio.request_free_list.next;
    request_index = l_req->self_index;
    luat_llist_del(&l_req->node);
    luat_llist_add_tail(&l_req->node, &_l_audio.request_busy_list);
    result = luat_audio_request_play_files(&l_req->request, NULL, NULL, info, file_nums, is_error_stop, priority, _l_audio_request_callback, l_req);
    luat_heap_free(info);
    if (result) {
        luat_llist_del(&l_req->node);
        luat_llist_add_tail(&l_req->node, &_l_audio.request_free_list);
    }
DONE:
    lua_pushboolean(L, !result);
    lua_pushinteger(L, request_index);
    return 2;
}

/*
配置调试信息输出
@api audio_v2.debug(on_off)
@boolean true开 false关
@return
@usage
audio_v2.debug(true)	--开启调试信息输出
audio_v2.debug(false)	--关闭调试信息输出
*/
static int l_audio_set_debug(lua_State *L) {
	luat_audio_debug_switch(lua_toboolean(L, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_audio_v2[] =
{
	{ "debug",			ROREG_FUNC(l_audio_set_debug)},
	{ "play",			ROREG_FUNC(l_audio_play)},
    { "on",				ROREG_FUNC(l_audio_on)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_audio_v2( lua_State *L ) {
    luat_newlib2(L, reg_audio_v2);
    return 1;
}
#endif