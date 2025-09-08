#include "luat_base.h"

#include "luat_lcd.h"
#include "luat_sdl2.h"
#include "luat_mem.h"

#include "lvgl.h"

static uint32_t* fb;

static inline uint32_t luat_color_565to8888(luat_color_t color);

static int sdl2_init(luat_lcd_conf_t* conf) {
    luat_sdl2_conf_t sdl2_conf = {
        .width = conf->w,
        .height = conf->h
    };
    luat_sdl2_init(&sdl2_conf);
    fb = luat_heap_malloc(sizeof(uint32_t) * conf->w * conf->h);
    luat_lcd_clear(conf, LCD_WHITE);
    // printf("ARGB8888 0xFFFF %08X\n", luat_color_565to8888(0xFFFF));
    // printf("ARGB8888 0X001F %08X\n", luat_color_565to8888(0X001F));
    // printf("ARGB8888 0xF800 %08X\n", luat_color_565to8888(0xF800));
    // printf("ARGB8888 0x0CE0 %08X\n", luat_color_565to8888(0x0CE0));
    return 0;
}

const luat_lcd_opts_t lcd_opts_sdl2 = {
    .name = "sdl2",
    .init = sdl2_init,
};

typedef struct luat_color_rgb565swap
{
    uint16_t blue : 5;
    uint16_t green : 6;
    uint16_t red : 5;
}luat_color_rgb565swap_t;

typedef struct luat_color_argb8888
{
    uint8_t blue;
    uint8_t green;
    uint8_t red;
    uint8_t alpha;
}luat_color_argb8888_t;


static inline uint32_t luat_color_565to8888(luat_color_t color) {
    luat_color_rgb565swap_t tmp;
    memcpy(&tmp, &color, sizeof(luat_color_rgb565swap_t));
    luat_color_argb8888_t dst = {
        .alpha = 0xFF,
        .red = (tmp.red * 263 + 7) >> 5,
        .green = (tmp.green * 259 + 3) >> 6,
        .blue = (tmp.blue *263  + 7) >> 5
    };
    uint32_t t;
    memcpy(&t, &dst, sizeof(luat_color_argb8888_t));
    //printf("ARGB8888 %08X\n", t);
    return t;
}

int luat_lcd_flush(luat_lcd_conf_t* conf) {
    luat_sdl2_flush();
    return 0;
}

int luat_lcd_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color_p) {
    size_t rw = x2 - x1 + 1;
    size_t rh = y2 - y1 + 1;

    uint32_t *tmp = fb;
    for (size_t i = 0; i < rh; i++)
    {
        for (size_t j = 0; j < rw; j++)
        {
            // 输入为 RGB565，SDL 纹理为 ARGB8888，这里做明确转换
            *tmp = luat_color_565to8888(*color_p);
            tmp ++;
            color_p ++;
        }
    }
    
    luat_sdl2_draw(x1, y1, x2, y2, fb);
    return 0;
}


