/**
 * @file luat_airui_input.c
 * @summary 系统键盘与输入相关的上下文管理
 * @responsible 聚焦管理、系统键盘事件分发
 */

#include "luat_airui.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>
#include <string.h>
#define LUAT_LOG_TAG "airui_input"
#include "luat_log.h"

/**
 * 设置当前聚焦的 textarea
 */
void airui_ctx_set_focused_textarea(airui_ctx_t *ctx, lv_obj_t *textarea) {
    if (ctx == NULL) {
        return;
    }
    ctx->focused_textarea = textarea;
}

lv_obj_t *airui_ctx_get_focused_textarea(airui_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    return ctx->focused_textarea;
}

/**
 * 系统键盘开关
 */
int airui_system_keyboard_enable(airui_ctx_t *ctx, bool enable) {
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    ctx->system_keyboard_enabled = enable ? 1 : 0;
    return AIRUI_OK;
}

bool airui_system_keyboard_is_enabled(airui_ctx_t *ctx) {
    if (ctx == NULL) return false;
    return ctx->system_keyboard_enabled;
}

static void airui_system_keyboard_insert_text(airui_ctx_t *ctx, const char *text) {
    if (ctx == NULL || ctx->focused_textarea == NULL || text == NULL) {
        return;
    }
    lv_textarea_add_text(ctx->focused_textarea, text);
}

void airui_system_keyboard_post_text(airui_ctx_t *ctx, const char *text) {
    if (!airui_system_keyboard_is_enabled(ctx) || text == NULL) {
        return;
    }
    airui_system_keyboard_insert_text(ctx, text);
}

void airui_system_keyboard_post_key(airui_ctx_t *ctx, uint32_t key, bool pressed) {
    if (ctx == NULL || ctx->focused_textarea == NULL || !airui_system_keyboard_is_enabled(ctx)) {
        return;
    }

    if (!pressed) {
        return;
    }

    lv_obj_t *textarea = ctx->focused_textarea;

    switch (key) {
        case LV_KEY_BACKSPACE:
            lv_textarea_delete_char(textarea);
            return;
        case LV_KEY_ENTER:
            lv_textarea_add_char(textarea, '\n');
            return;
        case LV_KEY_ESC:
            return;
        default:
            break;
    }

    if (key >= 32 && key < 127) {
        lv_textarea_add_char(textarea, (char)key);
    }
}

// 订阅触摸事件
int airui_touch_subscribe(airui_ctx_t *ctx, void *L, int callback_ref) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL || L_state == NULL || callback_ref <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (ctx->touch_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    }

    ctx->touch_callback_ref = callback_ref;
    ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
    ctx->touch_pressed = false;
    ctx->touch_last_point.x = 0;
    ctx->touch_last_point.y = 0;
    ctx->touch_last_track_id = 0;
    ctx->touch_last_timestamp = 0;
    memset(ctx->touch_active, 0, sizeof(ctx->touch_active));
    ctx->touch_active_count = 0;
    return AIRUI_OK;
}

// 取消触摸事件订阅
void airui_touch_unsubscribe(airui_ctx_t *ctx, void *L) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL) {
        return;
    }

    if (L_state != NULL && ctx->touch_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    }

    ctx->touch_callback_ref = 0;
    ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
    ctx->touch_pressed = false;
    ctx->touch_last_point.x = 0;
    ctx->touch_last_point.y = 0;
    ctx->touch_last_track_id = 0;
    ctx->touch_last_timestamp = 0;
    memset(ctx->touch_active, 0, sizeof(ctx->touch_active));
    ctx->touch_active_count = 0;
}

// 触摸事件坐标转换为逻辑坐标
static void airui_touch_map_to_logical(airui_ctx_t *ctx, lv_coord_t *x, lv_coord_t *y) {
    if (ctx == NULL || x == NULL || y == NULL || ctx->display == NULL) {
        return;
    }

    int32_t mapped_x = *x;
    int32_t mapped_y = *y;

    switch (lv_display_get_rotation(ctx->display)) {
        case LV_DISPLAY_ROTATION_180:
        case LV_DISPLAY_ROTATION_270:
            mapped_x = (int32_t)ctx->native_width - mapped_x - 1;
            mapped_y = (int32_t)ctx->native_height - mapped_y - 1;
            break;
        case LV_DISPLAY_ROTATION_0:
        case LV_DISPLAY_ROTATION_90:
        default:
            break;
    }

    switch (lv_display_get_rotation(ctx->display)) {
        case LV_DISPLAY_ROTATION_90:
        case LV_DISPLAY_ROTATION_270: {
            int32_t tmp = mapped_y;
            mapped_y = mapped_x;
            mapped_x = (int32_t)ctx->native_height - tmp - 1;
            break;
        }
        case LV_DISPLAY_ROTATION_0:
        case LV_DISPLAY_ROTATION_180:
        default:
            break;
    }

    *x = (lv_coord_t)mapped_x;
    *y = (lv_coord_t)mapped_y;
}

void airui_touch_notify(airui_ctx_t *ctx, const airui_touch_point_t *points, uint8_t count) {
    lua_State *L_state;
    uint8_t i;

    if (ctx == NULL || ctx->L == NULL) {
        return;
    }

    L_state = (lua_State *)ctx->L;
    if (ctx->touch_callback_ref <= 0) {
        return;
    }

    if (count > AIRUI_TOUCH_MAX_POINTS) {
        count = AIRUI_TOUCH_MAX_POINTS;
    }

    ctx->touch_pressed = false;
    for (i = 0; i < count; i++) {
        if (points[i].state == AIRUI_TOUCH_STATE_DOWN || points[i].state == AIRUI_TOUCH_STATE_HOLD) {
            ctx->touch_pressed = true;
            break;
        }
    }

    if (count > 0) {
        ctx->touch_last_state = points[0].state;
        ctx->touch_last_point.x = points[0].x;
        ctx->touch_last_point.y = points[0].y;
        ctx->touch_last_track_id = points[0].track_id;
        ctx->touch_last_timestamp = points[0].timestamp;
    } else {
        ctx->touch_last_state = AIRUI_TOUCH_STATE_UP;
        ctx->touch_last_timestamp = 0;
    }

    memset(ctx->touch_active, 0, sizeof(ctx->touch_active));
    ctx->touch_active_count = count;
    for (i = 0; i < count; i++) {
        ctx->touch_active[i] = points[i];
    }

    // 调用 Lua 回调: fn(state, x, y, track_id, timestamp, touches)
    lua_rawgeti(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    if (lua_type(L_state, -1) != LUA_TFUNCTION) {
        lua_pop(L_state, 1);
        return;
    }

    // 先压入旧格式 5 个独立参数（向后兼容）
    if (count > 0) {
        lv_coord_t first_x = points[0].x;
        lv_coord_t first_y = points[0].y;
        airui_touch_map_to_logical(ctx, &first_x, &first_y);
        lua_pushinteger(L_state, points[0].state);
        lua_pushinteger(L_state, first_x);
        lua_pushinteger(L_state, first_y);
        lua_pushinteger(L_state, points[0].track_id);
        lua_pushinteger(L_state, points[0].timestamp);
    } else {
        lv_coord_t last_x = ctx->touch_last_point.x;
        lv_coord_t last_y = ctx->touch_last_point.y;
        airui_touch_map_to_logical(ctx, &last_x, &last_y);
        lua_pushinteger(L_state, AIRUI_TOUCH_STATE_UP);
        lua_pushinteger(L_state, last_x);
        lua_pushinteger(L_state, last_y);
        lua_pushinteger(L_state, ctx->touch_last_track_id);
        lua_pushinteger(L_state, ctx->touch_last_timestamp);
    }

    // 再构建多触点 table（作为第 6 个参数）
    //   {[1]={state=1, x=100, y=200, track_id=0, timestamp=12345}, [2]=...}
    lua_createtable(L_state, count, 0);
    for (i = 0; i < count; i++) {
        const airui_touch_point_t *pt = &points[i];
        lv_coord_t x = pt->x;
        lv_coord_t y = pt->y;
        airui_touch_map_to_logical(ctx, &x, &y);

        lua_createtable(L_state, 0, 5);
        lua_pushinteger(L_state, pt->state);
        lua_setfield(L_state, -2, "state");
        lua_pushinteger(L_state, x);
        lua_setfield(L_state, -2, "x");
        lua_pushinteger(L_state, y);
        lua_setfield(L_state, -2, "y");
        lua_pushinteger(L_state, pt->track_id);
        lua_setfield(L_state, -2, "track_id");
        lua_pushinteger(L_state, pt->timestamp);
        lua_setfield(L_state, -2, "timestamp");
        lua_seti(L_state, -2, i + 1);
    }

    // 栈: [fn, state, x, y, track_id, timestamp, touches]
    if (lua_pcall(L_state, 6, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L_state, -1);
        LLOGE("touch callback error: %s", err ? err : "unknown");
        lua_pop(L_state, 1);
    }
}

// 订阅键盘事件
int airui_keypad_subscribe(airui_ctx_t *ctx, void *L, int callback_ref) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL || L_state == NULL || callback_ref <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (ctx->keypad_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    }

    ctx->keypad_callback_ref = callback_ref;
    ctx->keypad_last_key = 0;
    ctx->keypad_last_pressed = false;
    ctx->keypad_last_timestamp = 0;
    return AIRUI_OK;
}

// 取消键盘事件订阅
void airui_keypad_unsubscribe(airui_ctx_t *ctx, void *L) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL) {
        return;
    }

    if (L_state != NULL && ctx->keypad_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    }

    ctx->keypad_callback_ref = 0;
    ctx->keypad_last_key = 0;
    ctx->keypad_last_pressed = false;
    ctx->keypad_last_timestamp = 0;
}

// 通知键盘事件
void airui_keypad_notify(airui_ctx_t *ctx, uint32_t key, bool pressed, uint32_t timestamp) {
    lua_State *L_state;

    if (ctx == NULL || ctx->L == NULL) {
        return;
    }

    L_state = (lua_State *)ctx->L;
    if (ctx->keypad_callback_ref <= 0) {
        return;
    }

    ctx->keypad_last_key = key;
    ctx->keypad_last_pressed = pressed;
    ctx->keypad_last_timestamp = timestamp;

    lua_rawgeti(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    if (lua_type(L_state, -1) != LUA_TFUNCTION) {
        lua_pop(L_state, 1);
        return;
    }

    // 参数: key (SDL keycode), pressed (bool), timestamp
    lua_pushinteger(L_state, key);
    lua_pushboolean(L_state, pressed);
    lua_pushinteger(L_state, timestamp);

    if (lua_pcall(L_state, 3, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L_state, -1);
        LLOGE("keypad callback error: %s", err ? err : "unknown");
        lua_pop(L_state, 1);
    }
}
