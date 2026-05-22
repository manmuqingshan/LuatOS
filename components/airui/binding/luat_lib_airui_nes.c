#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.nes"
#include "luat_log.h"

#ifdef LUAT_USE_NES

static lv_obj_t *nes_check(lua_State *L) {
    return airui_check_component(L, 1, AIRUI_NES_MT);
}

static int l_airui_nes(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *nes = airui_nes_create_from_config(L, 1);
    if (!nes) {
        lua_pushnil(L);
        return 1;
    }
    airui_push_component_userdata(L, nes, AIRUI_NES_MT);
    return 1;
}

static int l_nes_destroy(lua_State *L) {
    return airui_component_destroy_userdata(L, 1, AIRUI_NES_MT);
}

static int l_nes_quit_requested(lua_State *L) {
    lv_obj_t *nes = nes_check(L);
    lua_pushboolean(L, airui_nes_quit_requested(nes));
    return 1;
}

void airui_register_nes_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_NES_MT);
    static const luaL_Reg methods[] = {
        {"destroy",         l_nes_destroy},
        {"quit_requested",  l_nes_quit_requested},
        {"is_destroyed",    airui_component_is_destroyed},
        {NULL, NULL}
    };
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_nes_create(lua_State *L) {
    return l_airui_nes(L);
}

#else  /* LUAT_USE_NES */

void airui_register_nes_meta(lua_State *L) {
    (void)L;
}

int airui_nes_create(lua_State *L) {
    lua_pushnil(L);
    return 1;
}

#endif /* LUAT_USE_NES */
