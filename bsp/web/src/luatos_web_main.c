#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_mcu.h"

#include "bget.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "luatos_web_bridge.h"

#define LUAT_LOG_TAG "web.main"
#include "luat_log.h"

extern void luat_mcu_startup_init(void);
extern void luat_log_init_win32(void);
extern void luat_openlibs(lua_State *L);

#define LUAT_HEAP_SIZE (4 * 1024 * 1024)
static uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int32_t luatos_pc_climode = 1;

static void web_heap_init(void) {
    luat_heap_opt_init(LUAT_HEAP_SRAM);
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_heap_opt_init(LUAT_HEAP_PSRAM);
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    web_heap_init();
    luat_mcu_startup_init();
    luat_log_init_win32();
    luatos_web_bridge_init();
    luatos_web_bridge_set_status("starting");

    lua_State *L = lua_newstate(luat_heap_alloc, NULL);
    if (L == NULL) {
        LLOGE("failed to create lua state");
        return 1;
    }
    luat_openlibs(L);
    if (luaL_dostring(L, "log.info('web', 'hello from LuatOS web')") != LUA_OK) {
        LLOGE("%s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    lua_close(L);
    return 0;
}
