/*
@module  httpsrv
@summary http服务端
@version 1.0
@date    2022.010.15
@demo wlan
@tag LUAT_USE_HTTPSRV
*/

#include "luat_base.h"
#include "luat_httpsrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#define LUAT_HTTPSRV_COUNT 16

typedef struct port_srv
{
    uint16_t port;
    uint8_t adapter;
    uint8_t status;
    luat_httpsrv_ctx_t* ctx;
}port_srv_t;

static port_srv_t srvs[LUAT_HTTPSRV_COUNT];

/*
启动并监听一个http端口
@api httpsrv.start(port, func, adapter)
@int 端口号
@function 回调函数
@int 网络适配器编号, 默认是平台自带的网络协议栈
@return bool 成功返回true, 否则返回false
@usage

-- 监听80端口
httpsrv.start(80, function(client, method, uri, headers, body)
    -- method 是字符串, 例如 GET POST PUT DELETE
    -- uri 也是字符串 例如 / /api/abc
    -- headers table类型
    -- body 字符串
    log.info("httpsrv", method, uri, json.encode(headers), body)
    if uri == "/led/1" then
        LEDA(1)
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        LEDA(0)
        return 200, {}, "ok"
    end
    -- 返回值的约定 code, headers, body
    -- 若没有返回值, 则默认 404, {} ,""
    return 404, {}, "Not Found" .. uri
end)
-- 关于静态文件
-- 情况1: / , 映射为 /index.html
-- 情况2: /abc.html , 先查找 /abc.html, 不存在的话查找 /abc.html.gz
-- 若gz存在, 会自动以压缩文件进行响应, 绝大部分浏览器支持.
-- 当前默认查找 /luadb/xxx 下的文件,暂不可配置
*/
static int l_httpsrv_start(lua_State *L) {
    // luat_ip_addr_t local_ip, net_mask, gate_way, ipv6;
    char buff[64] = {0};
    int port = luaL_checkinteger(L, 1);
    if (!lua_isfunction(L, 2)) {
        LLOGW("httpsrv need callback function!!!");
        return 0;
    }
    uint8_t adapter_index = luaL_optinteger(L, 3, network_register_get_default());
    luat_netdrv_t* drv = luat_netdrv_get(adapter_index);
    if (drv == NULL || drv->netif == NULL) {
        LLOGW("该网络还没准备好 %d", adapter_index);
        return 0;
    }
    // 检查一下是否有空位
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i].port == port && srvs[i].adapter == adapter_index) {
            LLOGW("httpsrv port %d already in use", port);
            return 0;
        }
    }
    int index = -1;
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i].ctx == NULL) {
            index = i;
            break;
        }
    }
    if (index < 0) {
        LLOGW("httpsrv no free slot, max %d", LUAT_HTTPSRV_COUNT);
        return 0;
    }

    luat_httpsrv_ctx_t* ctx = luat_httpsrv_malloc(port, adapter_index);
    if (ctx == NULL) {
        return 0;
    }
    ctx->netif = drv->netif;
    lua_pushvalue(L, 2);
    ctx->lua_ref_id = luaL_ref(L, LUA_REGISTRYINDEX);
    int ret = luat_httpsrv_start(ctx);
    if (ret == 0) {
        ipaddr_ntoa_r(&drv->netif->ip_addr, buff,  32);
        LLOGI("http listen at %s:%d", buff, ctx->port);
        srvs[index].port = port;
        srvs[index].adapter = adapter_index;
        srvs[index].ctx = ctx;
        srvs[index].status = 1;
    }
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
停止http服务
@api httpsrv.stop(port，no_used, adapter)
@int 端口号
@nil 固定写nil
@int 网络适配器编号, 默认是平台自带的网络协议栈
@return bool 成功返回true, 否则返回false
@usage
httpsrv.stop(SERVER_PORT,nil,socket.LWIP_AP)
*/
static int l_httpsrv_stop(lua_State *L) {
    int port = luaL_checkinteger(L, 1);
    uint8_t adapter_index = luaL_optinteger(L, 3, network_register_get_default());
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i].port == port && srvs[i].adapter == adapter_index) {
            if (srvs[i].ctx != NULL) {
                srvs[i].port = 0;
                srvs[i].adapter = 0;
                srvs[i].status = 0;
                
                if (srvs[i].ctx->lua_ref_id != LUA_NOREF) {
                    luaL_unref(L, LUA_REGISTRYINDEX, srvs[i].ctx->lua_ref_id);
                    srvs[i].ctx->lua_ref_id = LUA_NOREF;
                }
                luat_httpsrv_stop(srvs[i].ctx);
                srvs[i].ctx = NULL;
                lua_pushboolean(L, 1);
                return 1;
            }
        }
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_httpsrv[] =
{
    {"start",        ROREG_FUNC(l_httpsrv_start) },
    {"stop",         ROREG_FUNC(l_httpsrv_stop) },
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_httpsrv( lua_State *L ) {
    luat_newlib2(L, reg_httpsrv);
    return 1;
}
