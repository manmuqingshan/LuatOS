/**
 * @file luat_airui_checkbox.c
 * @summary Checkbox 组件
 * @responsible 解析配置、创建 lv_checkbox、设置样式、绑定事件
 */

#include "luat_airui_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/checkbox/lv_checkbox.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_group.h"
#include "lvgl9/src/misc/lv_color.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "airui_checkbox"
#include "luat_log.h"

static airui_ctx_t *airui_checkbox_get_ctx(lua_State *L)
{
    if (L == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 从 Lua config 创建 Checkbox 对象
 */
lv_obj_t *airui_checkbox_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_checkbox_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 24);
    int h = airui_marshal_floor_integer(L, idx, "h", 24);
    bool checked = airui_marshal_bool(L, idx, "checked", false);
    const char *text = airui_marshal_string(L, idx, "text", NULL);

    lv_obj_t *cb = lv_checkbox_create(parent);
    if (cb == NULL) {
        return NULL;
    }

    lv_obj_set_pos(cb, x, y);
    lv_obj_set_size(cb, w, h);

    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_checkbox_set_style(cb, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);

    if (checked) {
        lv_obj_add_state(cb, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(cb, LV_STATE_CHECKED);
    }

    if (text != NULL && strlen(text) > 0) {
        lv_checkbox_set_text(cb, text);
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, cb, AIRUI_COMPONENT_CHECKBOX);
    if (meta == NULL) {
        lv_obj_delete(cb);
        return NULL;
    }

    int callback_ref = airui_component_capture_callback(L, idx, "on_change");
    if (callback_ref != LUA_NOREF) {
        airui_checkbox_set_on_change(cb, callback_ref);
    }

    lv_group_t *default_group = lv_group_get_default();
    if (default_group != NULL) {
        lv_group_add_obj(default_group, cb);
    }

    return cb;
}

/**
 * 修改 Checkbox 的选中状态并派发事件
 */
int airui_checkbox_set_checked(lv_obj_t *cb, bool checked)
{
    if (cb == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    bool current = (lv_obj_get_state(cb) & LV_STATE_CHECKED) != 0;
    if (current == checked) {
        return AIRUI_OK;
    }

    if (checked) {
        lv_obj_add_state(cb, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(cb, LV_STATE_CHECKED);
    }

    lv_obj_send_event(cb, LV_EVENT_VALUE_CHANGED, NULL);
    return AIRUI_OK;
}

/**
 * 查询 Checkbox 是否处于选中状态
 */
bool airui_checkbox_get_checked(lv_obj_t *cb)
{
    if (cb == NULL) {
        return false;
    }

    return (lv_obj_get_state(cb) & LV_STATE_CHECKED) != 0;
}

/**
 * 设置 Checkbox 文本
 */
int airui_checkbox_set_text(lv_obj_t *cb, const char *text)
{
    if (cb == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_checkbox_set_text(cb, text != NULL ? text : "");
    return AIRUI_OK;
}

/**
 * 获取 Checkbox 文本
 */
const char *airui_checkbox_get_text(lv_obj_t *cb)
{
    if (cb == NULL) {
        return NULL;
    }

    return lv_checkbox_get_text(cb);
}

/**
 * 绑定状态变化回调
 */
int airui_checkbox_set_on_change(lv_obj_t *cb, int callback_ref)
{
    if (cb == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(cb);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(
        meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
}

/**
 * 设置 Checkbox 样式
 * 可设置的参数包括：
 *   - text_color: 默认态文字颜色，格式 0xRRGGBB
 *   - checked_text_color: 选中态文字颜色，格式 0xRRGGBB
 *   - text_font_size: 文字字号，单位像素
 */
int airui_checkbox_set_style(lv_obj_t *cb, void *L, int idx)
{
    if (cb == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int value = 0;

    if (airui_marshal_integer_opt(L_state, idx, "text_color", &value)) {
        lv_obj_set_style_text_color(cb, lv_color_hex((uint32_t)value),
            (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "checked_text_color", &value)) {
        lv_obj_set_style_text_color(cb, lv_color_hex((uint32_t)value),
            (lv_style_selector_t)LV_PART_MAIN | LV_STATE_CHECKED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "text_font_size", &value) && value > 0) {
        airui_text_font_apply_hzfont(cb, value,
            (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        airui_text_font_apply_hzfont(cb, value,
            (lv_style_selector_t)LV_PART_MAIN | LV_STATE_CHECKED);
    }

    return AIRUI_OK;
}
