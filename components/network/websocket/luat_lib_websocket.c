/*
@module  websocket
@summary websocket客户端
@version 1.0
@date    2022.11.28
@demo    websocket
@usage
local wsc = nil
if websocket then
	wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo")
    wsc:autoreconn(true, 3000) -- 自动重连机制
    wsc:on(function(wsc, event, data, fin, optcode)
    wsc:on(function(wsc, event, data)
        log.info("wsc", event, data)
        if event == "conack" then
            wsc:send((json.encode({action="echo", device_id=device_id})))
            sys.publish("wsc_conack")
        end
    end)
    wsc:connect()
    --sys.waitUntil("websocket_conack", 15000)
    while true do
        sys.wait(45000)
        if wsc:ready() then
        	wsc:send((json.encode({action="echo", msg=os.date()})))
		end
    end
    wsc:close()
    wsc = nil
end
*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_malloc.h"
#include "luat_websocket.h"

#define LUAT_LOG_TAG "websocket"
#include "luat_log.h"

#define LUAT_WEBSOCKET_CTRL_TYPE "WS*"

static luat_websocket_ctrl_t *get_websocket_ctrl(lua_State *L)
{
	if (luaL_testudata(L, 1, LUAT_WEBSOCKET_CTRL_TYPE))
	{
		return ((luat_websocket_ctrl_t *)luaL_checkudata(L, 1, LUAT_WEBSOCKET_CTRL_TYPE));
	}
	else
	{
		return ((luat_websocket_ctrl_t *)lua_touserdata(L, 1));
	}
}

static int32_t l_websocket_callback(lua_State *L, void *ptr)
{
	rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)msg->ptr;
	luat_websocket_pkg_t pkg = {0};
	// size_t payload_size = 0;
	switch (msg->arg1)
	{
	case WEBSOCKET_MSG_TIMER_PING:
	{
		luat_websocket_ping(websocket_ctrl);
		break;
	}
	case WEBSOCKET_MSG_RECONNECT:
	{
		luat_websocket_reconnect(websocket_ctrl);
		break;
	}
	case WEBSOCKET_MSG_PUBLISH:
	{
		if (websocket_ctrl->websocket_cb)
		{
			lua_geti(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_cb);
			if (lua_isfunction(L, -1))
			{
				lua_geti(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_ref);
				lua_pushstring(L, "recv");
				luat_websocket_payload((char *)msg->arg2, &pkg, 64 * 1024);
				lua_pushlstring(L, pkg.payload, pkg.plen);
				lua_pushinteger(L, pkg.FIN);
				lua_pushinteger(L, pkg.OPT_CODE);
				lua_call(L, 5, 0);
			}
		}
		luat_heap_free((char *)msg->arg2);
		break;
	}
	case WEBSOCKET_MSG_CONNACK:
	{
		if (websocket_ctrl->websocket_cb)
		{
			lua_geti(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_cb);
			if (lua_isfunction(L, -1))
			{
				lua_geti(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_ref);
				lua_pushstring(L, "conack");
				lua_call(L, 2, 0);
			}
			lua_getglobal(L, "sys_pub");
			if (lua_isfunction(L, -1))
			{
				lua_pushstring(L, "WEBSOCKET_CONNACK");
				lua_geti(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_ref);
				lua_call(L, 2, 0);
			}
		}
		break;
	}
	case WEBSOCKET_MSG_RELEASE:
	{
		if (websocket_ctrl->websocket_ref)
		{
			luaL_unref(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_ref);
			websocket_ctrl->websocket_ref = 0;
		}
		break;
	}
	default:
	{
		LLOGD("l_websocket_callback error arg1:%d", msg->arg1);
		break;
	}
	}
	// lua_pushinteger(L, 0);
	return 0;
}

int l_luat_websocket_msg_cb(luat_websocket_ctrl_t *ctrl, int arg1, int arg2)
{
	rtos_msg_t msg = {
		.handler = l_websocket_callback,
		.ptr = ctrl,
		.arg1 = arg1,
		.arg2 = arg2,
	};
	luat_msgbus_put(&msg, 0);
	return 0;
}

/*
配置是否打开debug信息
@api wsc:debug(onoff)
@boolean 是否打开debug开关
@return nil 无返回值
@usage wsc:debug(true)
*/
static int l_websocket_set_debug(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	if (lua_isboolean(L, 2))
	{
		websocket_ctrl->netc->is_debug = lua_toboolean(L, 2);
	}
	return 0;
}

/*
websocket客户端创建
@api websocket.create(adapter, url)
@int 适配器序号, 只能是network.ETH0,network.STA,network.AP,如果不填,会选择最后一个注册的适配器
@string 连接字符串,参考usage
@return userdata 若成功会返回websocket客户端实例,否则返回nil
@usage
-- 普通TCP链接
wsc = websocket.create(nil,"ws://air32.cn/abc")
-- 加密TCP链接
wsc = websocket.create(nil,"wss://air32.cn/abc")
*/
static int l_websocket_create(lua_State *L)
{
	int ret = 0;
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		return 0;
	}
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)lua_newuserdata(L, sizeof(luat_websocket_ctrl_t));
	if (!websocket_ctrl)
	{
		LLOGE("out of memory when malloc websocket_ctrl");
		return 0;
	}

	ret = luat_websocket_init(websocket_ctrl, adapter_index);
	if (ret)
	{
		LLOGE("websocket init FAID ret %d", ret);
		return 0;
	}

	luat_websocket_connopts_t opts = {0};

	// 连接参数相关
	const char *ip;
	size_t ip_len = 0;
#ifdef LUAT_USE_LWIP
	websocket_ctrl->ip_addr.type = 0xff;
#else
	websocket_ctrl->ip_addr.is_ipv6 = 0xff;
#endif
	opts.url = luaL_checklstring(L, 2, &ip_len);

	ret = luat_websocket_set_connopts(websocket_ctrl, luaL_checklstring(L, 2, &ip_len));

	// TODO 判断ret, 如果初始化失败, 应该终止

	luaL_setmetatable(L, LUAT_WEBSOCKET_CTRL_TYPE);
	lua_pushvalue(L, -1);
	websocket_ctrl->websocket_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	return 1;
}

/*
注册websocket回调
@api wsc:on(cb)
@function cb websocket回调,参数包括websocket_client, event, data, payload
@return nil 无返回值
@usage
wsc:on(function(websocket_client, event, data, payload)
	-- 用户自定义代码
	log.info("websocket", "event", event, websocket_client, data, payload)
end)
*/
static int l_websocket_on(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	if (websocket_ctrl->websocket_cb != 0)
	{
		luaL_unref(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_cb);
		websocket_ctrl->websocket_cb = 0;
	}
	if (lua_isfunction(L, 2))
	{
		lua_pushvalue(L, 2);
		websocket_ctrl->websocket_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	return 0;
}

/*
连接服务器
@api wsc:connect()
@return boolean 发起成功返回true, 否则返回false
@usage
-- 开始建立连接
wsc:connect()
-- 本函数仅代表发起成功, 后续仍需根据ready函数判断websocket是否连接正常
*/
static int l_websocket_connect(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	int ret = luat_websocket_connect(websocket_ctrl);
	if (ret)
	{
		LLOGE("socket connect ret=%d\n", ret);
		luat_websocket_close_socket(websocket_ctrl);
		lua_pushboolean(L, 0);
		return 1;
	}
	lua_pushboolean(L, 1);
	return 1;
}

/*
自动重连
@api wsc:autoreconn(reconnect, reconnect_time)
@bool 是否自动重连
@int 自动重连周期 单位ms 默认3000ms
@usage
wsc:autoreconn(true)
*/
static int l_websocket_autoreconn(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	if (lua_isboolean(L, 2))
	{
		websocket_ctrl->reconnect = lua_toboolean(L, 2);
	}
	websocket_ctrl->reconnect_time = luaL_optinteger(L, 3, 3000);
	if (websocket_ctrl->reconnect && websocket_ctrl->reconnect_time < 1000)
		websocket_ctrl->reconnect_time = 1000;
	return 0;
}

/*
发布消息
@api wsc:send(data, fin, opt)
@string 待发送的数据,必填
@int 是否为最后一帧,默认1
@int 操作码, 默认为字符串帧
@return int 消息id, 当qos为1或2时会有效值. 若底层返回是否, 会返回nil
@usage
wsc:publish("/luatos/123456", "123")
*/
static int l_websocket_send(lua_State *L)
{
	uint32_t payload_len = 0;
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	const char *payload = NULL;
	luat_zbuff_t *buff = NULL;
	int ret = 0;
	if (lua_isstring(L, 2))
	{
		payload = luaL_checklstring(L, 2, &payload_len);
	}
	else if (luaL_testudata(L, 2, LUAT_ZBUFF_TYPE))
	{
		buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
		payload = buff->addr;
		payload_len = buff->used;
	}
	else
	{
		LLOGD("only support string or zbuff");
		return 0;
	}
	luat_websocket_pkg_t pkg = {
		.FIN = 1,
		.OPT_CODE = 0x01,
		.plen = payload_len,
		.payload = payload};
	ret = luat_websocket_send_frame(websocket_ctrl, &pkg);
	return 0;
}

/*
websocket客户端关闭(关闭后资源释放无法再使用)
@api wsc:close()
@usage
wsc:close()
*/
static int l_websocket_close(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	// websocket_disconnect(&(websocket_ctrl->broker));
	luat_websocket_close_socket(websocket_ctrl);
	if (websocket_ctrl->websocket_cb != 0)
	{
		luaL_unref(L, LUA_REGISTRYINDEX, websocket_ctrl->websocket_cb);
		websocket_ctrl->websocket_cb = 0;
	}
	luat_websocket_release_socket(websocket_ctrl);
	return 0;
}

/*
websocket客户端是否就绪
@api wsc:ready()
@return bool 客户端是否就绪
@usage
local error = wsc:ready()
*/
static int l_websocket_ready(lua_State *L)
{
	luat_websocket_ctrl_t *websocket_ctrl = get_websocket_ctrl(L);
	lua_pushboolean(L, websocket_ctrl->websocket_state > 0 ? 1 : 0);
	return 1;
}

static int _websocket_struct_newindex(lua_State *L);

void luat_websocket_struct_init(lua_State *L)
{
	luaL_newmetatable(L, LUAT_WEBSOCKET_CTRL_TYPE);
	lua_pushcfunction(L, _websocket_struct_newindex);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_websocket[] =
	{
		{"create", ROREG_FUNC(l_websocket_create)},
		{"on", ROREG_FUNC(l_websocket_on)},
		{"connect", ROREG_FUNC(l_websocket_connect)},
		{"autoreconn", ROREG_FUNC(l_websocket_autoreconn)},
		{"send", ROREG_FUNC(l_websocket_send)},
		{"close", ROREG_FUNC(l_websocket_close)},
		{"ready", ROREG_FUNC(l_websocket_ready)},

		{NULL, ROREG_INT(0)}};

static int _websocket_struct_newindex(lua_State *L)
{
	rotable_Reg_t *reg = reg_websocket;
	const char *key = luaL_checkstring(L, 2);
	while (1)
	{
		if (reg->name == NULL)
			return 0;
		if (!strcmp(reg->name, key))
		{
			lua_pushcfunction(L, reg->value.value.func);
			return 1;
		}
		reg++;
	}
	// return 0;
}
static const rotable_Reg_t reg_websocket_emtry[] =
	{
		{NULL, ROREG_INT(0)}};

LUAMOD_API int luaopen_websocket(lua_State *L)
{

#ifdef LUAT_USE_NETWORK
	luat_newlib2(L, reg_websocket);
	luat_websocket_struct_init(L);
	return 1;
#else
	LLOGE("websocket require network enable!!");
	luat_newlib2(L, reg_websocket_emtry);
	return 1;
#endif
}