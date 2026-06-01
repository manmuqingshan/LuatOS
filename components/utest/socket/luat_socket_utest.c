#include "luat_base.h"
#include <string.h>

#define LUAT_LOG_TAG "socket_utest"
#include "luat_log.h"

static int finish_socket_utest(lua_State *L, int status, lua_KContext ctx) {
    (void)ctx;
    if (status != LUA_OK && status != LUA_YIELD) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, lua_toboolean(L, -1));
    return 1;
}

static const char *get_socket_utest_code(const char *case_name) {
    if (!case_name || strcmp(case_name, "tcp_external_qq") == 0) {
        return
            "local ready = false "
            "for _ = 1, 30 do "
            "  local adapter = socket.dft() "
            "  local ok = socket.adapter(adapter) "
            "  local ip = socket.localIP(adapter) "
            "  if ok and type(ip) == 'string' and ip ~= '0.0.0.0' then "
            "    ready = true "
            "    break "
            "  end "
            "  sys.wait(1000) "
            "end "
            "assert(ready, 'network not ready') "
            "local function wait_evt(topic, expected, timeout) "
            "  local result, evt, param = sys.waitUntil(topic, timeout) "
            "  return result ~= false and evt == expected and param == 0 "
            "end "
            "local function attempt_once(attempt) "
            "  local topic = 'tcp_utest_event_' .. attempt "
            "  local netc = socket.create(nil, function(_, evt, param) sys.publish(topic, evt, param) end) "
            "  assert(netc, 'socket.create failed') "
            "  assert(socket.config(netc, nil, false, false), 'socket.config failed') "
            "  local succ, online = socket.connect(netc, 'www.qq.com', 80) "
            "  assert(succ, 'socket.connect failed') "
            "  if not online then "
            "    assert(wait_evt(topic, socket.ON_LINE, 30000), 'socket connect timeout') "
            "  end "
            "  local tx_succ, full, tx_done = socket.tx(netc, 'HEAD / HTTP/1.1\\r\\nHost: www.qq.com\\r\\nConnection: close\\r\\n\\r\\n') "
            "  assert(tx_succ and not full, 'socket.tx failed') "
            "  if not tx_done then "
            "    assert(wait_evt(topic, socket.TX_OK, 30000), 'socket tx timeout') "
            "  end "
            "  local data = '' "
            "  for _ = 1, 30 do "
            "    local read_ok, read_data = socket.read(netc, 1024) "
            "    if read_ok and type(read_data) == 'string' and #read_data > 0 then "
            "      data = read_data "
            "      break "
            "    end "
            "    local result, _, param = sys.waitUntil(topic, 1000) "
            "    if result ~= false and param == -1 then "
            "      break "
            "    end "
            "  end "
            "  local close_succ, closed = socket.discon(netc) "
            "  if close_succ and not closed then "
            "    sys.waitUntil(topic, 5000) "
            "  end "
            "  socket.close(netc) "
            "  return #data > 0 and string.find(data, 'HTTP/', 1, true) ~= nil "
            "end "
            "for attempt = 1, 3 do "
            "  local ok, result = pcall(attempt_once, attempt) "
            "  if ok and result then "
            "    return true "
            "  end "
            "  if attempt < 3 then "
            "    sys.wait(1000) "
            "  end "
            "end "
            "return false";
    }
    return NULL;
}

int luat_socket_utest(lua_State *L, const char *case_name) {
    const char *code = get_socket_utest_code(case_name);
    int status;
    if (!code) {
        lua_pushboolean(L, 0);
        return 1;
    }
    if (luaL_loadstring(L, code) != LUA_OK) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        return 1;
    }
    status = lua_pcallk(L, 0, 1, 0, 0, finish_socket_utest);
    return finish_socket_utest(L, status, 0);
}
