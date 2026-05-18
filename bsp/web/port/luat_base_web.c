#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "main.web"
#include "luat_log.h"

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base},
  {LUA_LOADLIBNAME, luaopen_package},
  {LUA_COLIBNAME, luaopen_coroutine},
  {LUA_TABLIBNAME, luaopen_table},
  {LUA_IOLIBNAME, luaopen_io},
  {LUA_OSLIBNAME, luaopen_os},
  {LUA_STRLIBNAME, luaopen_string},
  {LUA_MATHLIBNAME, luaopen_math},
  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},
  {"log", luaopen_log},
  {"mcu", luaopen_mcu},
  {"uart", luaopen_uart},
  {NULL, NULL}
};

void luat_openlibs(lua_State *L) {
    const luaL_Reg *lib;
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);
    }
}

const char* luat_os_bsp(void) {
    return "WEB";
}

void luat_os_print_heapinfo(const char* tag) {
    (void)tag;
}

void luat_os_reboot(int code) {
    exit(code);
}

void luat_task_suspend_all(void) {}
void luat_task_resume_all(void) {}
