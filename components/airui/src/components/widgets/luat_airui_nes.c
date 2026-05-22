#include "luat_airui_component.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "lua.h"
#include "lauxlib.h"
#include "nes.h"
#include "nes_port.h"
#include <lvgl.h>
#include <string.h>

#ifdef LUAT_USE_AIRUI
#ifdef LUAT_USE_NES

#define LUAT_LOG_TAG "airui.nes"
#include "luat_log.h"

/* ========== 常量（固定 320x480 竖屏游戏容器）========== */

#define NES_SCREEN_W     256
#define NES_SCREEN_H     240
#define NES_CONTAINER_W  320
#define NES_CONTAINER_H  480

#define HEADER_H         32
#define CONTROLS_H       208   /* 480 - HEADER_H - NES_SCREEN_H(scale=1) */

#define BTN_SIZE_A       50
#define BTN_SIZE_B       42
#define DPAD_BTN_SIZE    40
#define DPAD_AREA_SIZE   118
#define AB_AREA_SIZE     118

#define CTRL_PAD_X       6
#define CTRL_PAD_Y       4

/* ========== 按键 ID ========== */

enum {
    NES_KEY_UP = 1,
    NES_KEY_DOWN,
    NES_KEY_LEFT,
    NES_KEY_RIGHT,
    NES_KEY_A,
    NES_KEY_B,
    NES_KEY_START,
    NES_KEY_SELECT
};

/* ========== 私有数据 ========== */

typedef struct {
    nes_t *nes_ctx;
    luat_rtos_task_handle nes_thread;

    lv_obj_t *main_container;
    lv_obj_t *game_screen;
    lv_obj_t *controls_container;
    lv_obj_t *title_bar;

    uint16_t *framebuffer;
    lv_image_dsc_t img_dsc;

    char *rom_path;
    int scale;
    int show_controls;
    int show_header;

    volatile int refresh_pending;
    volatile int quit_requested;
    int initialized;
} airui_nes_data_t;

/* ========== 前向声明 ========== */

static int  _nes_refresh_handler(lua_State *L, void *ptr);
static int  _nes_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels);
static void _nes_frame_cb(void *ctx);
static void _nes_release_data(void *user_data);

static void _btn_back_cb(lv_event_t *e);
static void _btn_event_cb(lv_event_t *e);

static airui_ctx_t *airui_nes_get_ctx(lua_State *L_state);

static int _nes_avail_game_h(int show_header, int show_controls) {
    int h = NES_CONTAINER_H;
    if (show_header)   h -= HEADER_H;
    if (show_controls) h -= CONTROLS_H;
    return h;
}

static int _nes_clamp_scale(int scale, int show_header, int show_controls) {
    int avail_h = _nes_avail_game_h(show_header, show_controls);
    int max_scale_w = (NES_CONTAINER_W - 8) / NES_SCREEN_W;
    int max_scale_h = (avail_h > 8) ? (avail_h - 8) / NES_SCREEN_H : 1;
    int max_scale = max_scale_w < max_scale_h ? max_scale_w : max_scale_h;
    if (max_scale < 1) max_scale = 1;
    if (scale > max_scale) scale = max_scale;
    if (scale < 1) scale = 1;
    return scale;
}

/* ========== 从主容器获取私有数据 ========== */

static airui_nes_data_t *_get_data_from_event(lv_event_t *e) {
    lv_obj_t *obj = lv_event_get_target(e);
    while (obj) {
        airui_component_meta_t *meta = airui_component_meta_get(obj);
        if (meta && meta->component_type == AIRUI_COMPONENT_NES) {
            return (airui_nes_data_t *)meta->user_data;
        }
        obj = lv_obj_get_parent(obj);
    }
    return NULL;
}

/* ========== 按键映射 ========== */

static void _set_nes_key_from_event(lv_event_t *e, int key, int pressed) {
    airui_nes_data_t *data = _get_data_from_event(e);
    if (!data || !data->nes_ctx) return;
    switch (key) {
        case NES_KEY_UP:     data->nes_ctx->nes_cpu.joypad.U1  = pressed; break;
        case NES_KEY_DOWN:   data->nes_ctx->nes_cpu.joypad.D1  = pressed; break;
        case NES_KEY_LEFT:   data->nes_ctx->nes_cpu.joypad.L1  = pressed; break;
        case NES_KEY_RIGHT:  data->nes_ctx->nes_cpu.joypad.R1  = pressed; break;
        case NES_KEY_A:      data->nes_ctx->nes_cpu.joypad.A1  = pressed; break;
        case NES_KEY_B:      data->nes_ctx->nes_cpu.joypad.B1  = pressed; break;
        case NES_KEY_START:  data->nes_ctx->nes_cpu.joypad.ST1 = pressed; break;
        case NES_KEY_SELECT: data->nes_ctx->nes_cpu.joypad.SE1 = pressed; break;
        default: break;
    }
}

/* ========== LVGL 回调 ========== */

static void _btn_back_cb(lv_event_t *e) {
    airui_nes_data_t *data = (airui_nes_data_t *)lv_event_get_user_data(e);
    if (data) data->quit_requested = 1;
}

static void _btn_event_cb(lv_event_t *e) {
    lv_event_code_t code = lv_event_get_code(e);
    int key_id = (int)(intptr_t)lv_event_get_user_data(e);
    if (code == LV_EVENT_PRESSED) {
        _set_nes_key_from_event(e, key_id, 1);
    } else if (code == LV_EVENT_RELEASED) {
        _set_nes_key_from_event(e, key_id, 0);
    }
}

/* ========== UI 创建 ========== */

static void _make_dpad_btn(lv_obj_t *parent, lv_align_t align, int key_id, airui_nes_data_t *data) {
    lv_obj_t *btn = lv_btn_create(parent);
    lv_obj_set_size(btn, DPAD_BTN_SIZE, DPAD_BTN_SIZE);
    lv_obj_set_style_bg_color(btn, lv_color_hex(0x34495E), 0);
    lv_obj_set_style_radius(btn, 8, 0);
    lv_obj_align(btn, align, 0, 0);
    lv_obj_add_event_cb(btn, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)key_id);
    lv_obj_add_event_cb(btn, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)key_id);
}

static void _create_title_bar(airui_nes_data_t *data) {
    data->title_bar = lv_obj_create(data->main_container);
    lv_obj_set_size(data->title_bar, NES_CONTAINER_W, HEADER_H);
    lv_obj_set_style_bg_color(data->title_bar, lv_color_hex(0x16213E), 0);
    lv_obj_set_style_border_width(data->title_bar, 0, 0);
    lv_obj_set_style_pad_hor(data->title_bar, 4, 0);
    lv_obj_set_style_pad_ver(data->title_bar, 2, 0);
    lv_obj_clear_flag(data->title_bar, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *btn_back = lv_btn_create(data->title_bar);
    lv_obj_set_size(btn_back, 56, 26);
    lv_obj_align(btn_back, LV_ALIGN_LEFT_MID, 2, 0);
    lv_obj_set_style_bg_color(btn_back, lv_color_hex(0xE74C3C), 0);
    lv_obj_set_style_radius(btn_back, 6, 0);
    lv_obj_t *lbl = lv_label_create(btn_back);
    lv_label_set_text(lbl, LV_SYMBOL_LEFT " Exit");
    lv_obj_center(lbl);
    lv_obj_add_event_cb(btn_back, _btn_back_cb, LV_EVENT_CLICKED, data);

    lv_obj_t *title = lv_label_create(data->title_bar);
    lv_label_set_text(title, "LuatOS NES");
    lv_obj_set_style_text_color(title, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_14, 0);
    lv_obj_align(title, LV_ALIGN_CENTER, 24, 0);
}

static void _create_game_screen(airui_nes_data_t *data, int game_area_h) {
    size_t buf_size = NES_SCREEN_W * NES_SCREEN_H * sizeof(uint16_t);
    data->framebuffer = lv_malloc(buf_size);
    if (!data->framebuffer) {
        LLOGE("NES: framebuffer alloc failed");
        return;
    }
    memset(data->framebuffer, 0, buf_size);

    lv_obj_t *game_area = lv_obj_create(data->main_container);
    lv_obj_set_size(game_area, NES_CONTAINER_W, game_area_h);
    lv_obj_set_layout(game_area, LV_LAYOUT_NONE);
    lv_obj_clear_flag(game_area, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(game_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(game_area, 0, 0);
    lv_obj_set_style_pad_all(game_area, 0, 0);

    data->game_screen = lv_image_create(game_area);

    data->img_dsc = (lv_image_dsc_t){
        .header = {
            .magic  = LV_IMAGE_HEADER_MAGIC,
            .cf     = LV_COLOR_FORMAT_RGB565,
            .w      = NES_SCREEN_W,
            .h      = NES_SCREEN_H,
            .stride = NES_SCREEN_W * sizeof(uint16_t),
            .flags  = 0,
        },
        .data_size = buf_size,
        .data      = (const uint8_t *)data->framebuffer,
        .reserved  = NULL,
        .reserved_2 = NULL,
    };
    lv_image_set_src(data->game_screen, &data->img_dsc);

    if (data->scale > 1) {
        lv_image_set_scale(data->game_screen, data->scale * 256);
    }
    lv_obj_set_size(data->game_screen,
                    NES_SCREEN_W  * data->scale,
                    NES_SCREEN_H * data->scale);
    lv_obj_set_style_border_width(data->game_screen, 2, 0);
    lv_obj_set_style_border_color(data->game_screen, lv_color_hex(0x0F3460), 0);
    lv_obj_set_style_radius(data->game_screen, 2, 0);
    lv_obj_set_style_pad_all(data->game_screen, 0, 0);
    lv_obj_align(data->game_screen, LV_ALIGN_CENTER, 0, 0);
}

static void _create_controls(airui_nes_data_t *data) {
    data->controls_container = lv_obj_create(data->main_container);
    lv_obj_set_size(data->controls_container, NES_CONTAINER_W, CONTROLS_H);
    lv_obj_set_layout(data->controls_container, LV_LAYOUT_NONE);
    lv_obj_clear_flag(data->controls_container, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(data->controls_container, LV_OPA_20, 0);
    lv_obj_set_style_bg_color(data->controls_container, lv_color_hex(0x0F3460), 0);
    lv_obj_set_style_border_width(data->controls_container, 0, 0);
    lv_obj_set_style_pad_all(data->controls_container, 0, 0);

    /* 十字键（左侧） */
    lv_obj_t *dpad = lv_obj_create(data->controls_container);
    lv_obj_set_size(dpad, DPAD_AREA_SIZE, DPAD_AREA_SIZE);
    lv_obj_set_layout(dpad, LV_LAYOUT_NONE);
    lv_obj_clear_flag(dpad, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(dpad, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(dpad, 0, 0);
    lv_obj_set_style_pad_all(dpad, 0, 0);
    lv_obj_align(dpad, LV_ALIGN_LEFT_MID, CTRL_PAD_X, -18);
    _make_dpad_btn(dpad, LV_ALIGN_TOP_MID,    NES_KEY_UP,    data);
    _make_dpad_btn(dpad, LV_ALIGN_BOTTOM_MID, NES_KEY_DOWN,  data);
    _make_dpad_btn(dpad, LV_ALIGN_LEFT_MID,   NES_KEY_LEFT,  data);
    _make_dpad_btn(dpad, LV_ALIGN_RIGHT_MID,  NES_KEY_RIGHT, data);

    /* A/B（右侧） */
    lv_obj_t *ab = lv_obj_create(data->controls_container);
    lv_obj_set_size(ab, AB_AREA_SIZE, AB_AREA_SIZE);
    lv_obj_set_layout(ab, LV_LAYOUT_NONE);
    lv_obj_clear_flag(ab, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(ab, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(ab, 0, 0);
    lv_obj_set_style_pad_all(ab, 0, 0);
    lv_obj_align(ab, LV_ALIGN_RIGHT_MID, -CTRL_PAD_X, -18);

    lv_obj_t *btn_b = lv_btn_create(ab);
    lv_obj_set_size(btn_b, BTN_SIZE_B, BTN_SIZE_B);
    lv_obj_set_style_bg_color(btn_b, lv_color_hex(0x3498DB), 0);
    lv_obj_set_style_radius(btn_b, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_b, LV_ALIGN_BOTTOM_LEFT, 6, -6);
    lv_obj_t *lbl_b = lv_label_create(btn_b);
    lv_label_set_text(lbl_b, "B");
    lv_obj_set_style_text_color(lbl_b, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(lbl_b);
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)NES_KEY_B);
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)NES_KEY_B);

    lv_obj_t *btn_a = lv_btn_create(ab);
    lv_obj_set_size(btn_a, BTN_SIZE_A, BTN_SIZE_A);
    lv_obj_set_style_bg_color(btn_a, lv_color_hex(0xE74C3C), 0);
    lv_obj_set_style_radius(btn_a, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_a, LV_ALIGN_TOP_RIGHT, -6, 6);
    lv_obj_t *lbl_a = lv_label_create(btn_a);
    lv_label_set_text(lbl_a, "A");
    lv_obj_set_style_text_color(lbl_a, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(lbl_a);
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)NES_KEY_A);
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)NES_KEY_A);

    /* SELECT + START（底部居中） */
    lv_obj_t *btn_sel = lv_btn_create(data->controls_container);
    lv_obj_set_size(btn_sel, 68, 28);
    lv_obj_set_style_bg_color(btn_sel, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_sel, 14, 0);
    lv_obj_align(btn_sel, LV_ALIGN_BOTTOM_MID, -42, -CTRL_PAD_Y);
    lv_obj_t *lbl_sel = lv_label_create(btn_sel);
    lv_label_set_text(lbl_sel, "SEL");
    lv_obj_center(lbl_sel);
    lv_obj_add_event_cb(btn_sel, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)NES_KEY_SELECT);
    lv_obj_add_event_cb(btn_sel, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)NES_KEY_SELECT);

    lv_obj_t *btn_start = lv_btn_create(data->controls_container);
    lv_obj_set_size(btn_start, 68, 28);
    lv_obj_set_style_bg_color(btn_start, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_start, 14, 0);
    lv_obj_align(btn_start, LV_ALIGN_BOTTOM_MID, 42, -CTRL_PAD_Y);
    lv_obj_t *lbl_start = lv_label_create(btn_start);
    lv_label_set_text(lbl_start, "START");
    lv_obj_center(lbl_start);
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)NES_KEY_START);
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)NES_KEY_START);
}

/* ========== NES 渲染回调（NES 线程中调用）========== */

static int _nes_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels_in) {
    airui_nes_data_t *data = (airui_nes_data_t *)ctx;
    nes_color_t *pixels = (nes_color_t *)pixels_in;
    if (!data || !data->initialized || !data->framebuffer) return -1;
    if (!pixels) return -2;
    if (x1 >= NES_SCREEN_W || y1 >= NES_SCREEN_H) return -3;
    if (x2 >= NES_SCREEN_W)  x2 = NES_SCREEN_W  - 1;
    if (y2 >= NES_SCREEN_H) y2 = NES_SCREEN_H - 1;

    size_t cols = x2 - x1 + 1;
    size_t rows = y2 - y1 + 1;

#if (NES_COLOR_SWAP == 0)
    for (size_t row = 0; row < rows; row++) {
        uint16_t *dst = data->framebuffer + (y1 + row) * NES_SCREEN_W + x1;
        const nes_color_t *src = pixels + row * cols;
        memcpy(dst, src, cols * sizeof(uint16_t));
    }
#else
    for (size_t row = 0; row < rows; row++) {
        uint16_t *dst = data->framebuffer + (y1 + row) * NES_SCREEN_W + x1;
        const nes_color_t *src = pixels + row * cols;
        for (size_t col = 0; col < cols; col++) {
            uint16_t v = src[col];
            dst[col] = (uint16_t)((v >> 8) | (v << 8));
        }
    }
#endif
    return 0;
}

static void _nes_frame_cb(void *ctx) {
    airui_nes_data_t *data = (airui_nes_data_t *)ctx;
    if (!data || !data->initialized || !data->game_screen) return;
    if (data->refresh_pending) return;
    data->refresh_pending = 1;
    rtos_msg_t msg = {
        .handler = _nes_refresh_handler,
        .ptr     = data,
        .arg1    = 0,
        .arg2    = 0,
    };
    if (luat_msgbus_put(&msg, 0) != 0) {
        data->refresh_pending = 0;
    }
}

/* ========== msgbus 刷新 handler（Lua 主线程中执行）========== */

static int _nes_refresh_handler(lua_State *L, void *ptr) {
    (void)L;
    airui_nes_data_t *data = (airui_nes_data_t *)ptr;
    if (!data || !data->initialized || !data->game_screen) return 0;
    lv_obj_invalidate(data->game_screen);
    data->refresh_pending = 0;
    return 0;
}

/* ========== NES 任务入口 ========== */

static void _nes_task_entry(void *param) {
    nes_t *ctx = (nes_t *)param;
    if (!ctx) return;
    nes_run(ctx);
}

/* ========== 销毁 ========== */

static void _nes_release_data(void *user_data) {
    airui_nes_data_t *data = (airui_nes_data_t *)user_data;
    if (!data) return;

    data->initialized = 0;

    /* 清除渲染回调，禁止 NES 线程再写入我们的 framebuffer */
    nes_port_clear_render_cb();

    /* 通知 NES 线程退出 */
    if (data->nes_ctx) {
        data->nes_ctx->nes_quit = 1;
    }

    /* 等待 NES 线程退出（轮询，最大约 500ms） */
    if (data->nes_thread) {
        int timeout = 50;
        while (timeout-- > 0) {
            luat_rtos_task_sleep(10);
        }
        luat_rtos_task_delete(data->nes_thread);
        data->nes_thread = 0;
    }

    if (data->nes_ctx) {
        nes_deinit(data->nes_ctx);
        data->nes_ctx = NULL;
    }

    if (data->framebuffer) {
        lv_free(data->framebuffer);
        data->framebuffer = NULL;
    }

    if (data->rom_path) {
        luat_heap_free(data->rom_path);
        data->rom_path = NULL;
    }

    luat_heap_free(data);
}

/* ========== 公共 API ========== */

static airui_ctx_t *airui_nes_get_ctx(lua_State *L_state) {
    airui_ctx_t *ctx = NULL;
    if (L_state == NULL) return NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

lv_obj_t *airui_nes_create_from_config(void *L, int idx) {
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_nes_get_ctx(L_state);

    const char *rom = airui_marshal_string(L, idx, "rom", NULL);
    if (!rom) {
        LLOGE("NES: 'rom' is required");
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    if (!parent) {
        parent = lv_screen_active();
    }
    if (!parent) {
        LLOGE("NES: no parent or active screen");
        return NULL;
    }

    int scale         = airui_marshal_integer(L, idx, "scale", 0);
    int show_controls = airui_marshal_integer(L, idx, "show_controls", 1);
    int show_header   = airui_marshal_integer(L, idx, "show_header", 1);

    if (scale == 0) {
        scale = 1;
    }
    if (scale > 3) scale = 3;
    scale = _nes_clamp_scale(scale, show_header, show_controls);

    /* 创建主容器（固定 320x480） */
    lv_obj_t *main_container = lv_obj_create(parent);
    lv_obj_set_size(main_container, NES_CONTAINER_W, NES_CONTAINER_H);
    lv_obj_set_layout(main_container, LV_LAYOUT_FLEX);
    lv_obj_set_flex_flow(main_container, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(main_container, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_bg_color(main_container, lv_color_hex(0x1A1A2E), 0);
    lv_obj_set_style_pad_gap(main_container, 0, 0);
    lv_obj_set_style_pad_all(main_container, 0, 0);
    lv_obj_set_style_border_width(main_container, 0, 0);
    lv_obj_clear_flag(main_container, LV_OBJ_FLAG_SCROLLABLE);

    /* 分配元数据 */
    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, main_container, AIRUI_COMPONENT_NES);
    if (!meta) {
        lv_obj_delete(main_container);
        return NULL;
    }

    /* 分配私有数据 */
    airui_nes_data_t *data = (airui_nes_data_t *)luat_heap_malloc(sizeof(airui_nes_data_t));
    if (!data) {
        lv_obj_delete(main_container);
        return NULL;
    }
    memset(data, 0, sizeof(airui_nes_data_t));
    data->main_container = main_container;
    data->scale          = scale;
    data->show_controls  = show_controls;
    data->show_header    = show_header;
    data->rom_path       = (char *)luat_heap_malloc(strlen(rom) + 1);
    if (data->rom_path) {
        strcpy(data->rom_path, rom);
    }

    /* 创建 UI */
    int game_area_h = _nes_avail_game_h(show_header, show_controls);
    if (show_header) {
        _create_title_bar(data);
    }
    _create_game_screen(data, game_area_h);
    if (show_controls) {
        _create_controls(data);
    }

    /* 初始化 NES 核心 */
    data->nes_ctx = nes_init();
    if (!data->nes_ctx) {
        LLOGE("NES: nes_init failed");
        _nes_release_data(data);
        lv_obj_delete(main_container);
        return NULL;
    }
    nes_load_file(data->nes_ctx, rom);

    /* 创建 NES 渲染线程 */
    if (luat_rtos_task_create(&data->nes_thread, 8 * 1024, 27,
                              "airui_nes", _nes_task_entry, data->nes_ctx, 0)) {
        LLOGE("NES: task create failed");
        _nes_release_data(data);
        lv_obj_delete(main_container);
        return NULL;
    }

    /* 注册渲染回调 */
    nes_port_render_cb_t cb = {
        .draw  = _nes_draw_cb,
        .frame = _nes_frame_cb,
        .ctx   = data,
    };
    nes_port_set_render_cb(&cb);

    data->initialized = 1;

    /* 绑定私有数据到元数据 */
    airui_component_meta_set_user_data(meta, data, _nes_release_data);

    return main_container;
}

int airui_nes_destroy(lv_obj_t *nes) {
    if (!nes) return 0;
    airui_component_meta_t *meta = airui_component_meta_get(nes);
    if (meta) {
        airui_component_meta_free(meta);
    }
    lv_obj_delete(nes);
    return 0;
}

int airui_nes_quit_requested(lv_obj_t *nes) {
    airui_component_meta_t *meta = airui_component_meta_get(nes);
    if (!meta || !meta->user_data) return 0;
    airui_nes_data_t *data = (airui_nes_data_t *)meta->user_data;
    return data->quit_requested;
}

#endif /* LUAT_USE_NES */
#endif /* LUAT_USE_AIRUI */
