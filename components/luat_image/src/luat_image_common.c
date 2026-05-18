#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"

#include "luat_image_common.h"

int luat_image_prepare_output(luat_img_info_t* img_info, uint16_t width, uint16_t height) {
    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    img_info->width = width;
    img_info->height = height;
    img_info->size = (uint32_t)width * height * sizeof(luat_color_t);
    img_info->data = (uint8_t*)luat_heap_malloc(img_info->size);
    if (img_info->data == NULL) {
        return LUAT_IMG_ERR;
    }
    return LUAT_IMG_OK;
}

static luat_color_t luat_image_rgb_to_color(uint8_t r, uint8_t g, uint8_t b) {
#if (LUAT_LCD_COLOR_DEPTH == 32)
    return (luat_color_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
#elif (LUAT_LCD_COLOR_DEPTH == 16)
    return (luat_color_t)(((luat_color_t)(r >> 3) << 11) |
                          ((luat_color_t)(g >> 2) << 5) |
                          (luat_color_t)(b >> 3));
#elif (LUAT_LCD_COLOR_DEPTH == 8)
    return (luat_color_t)((54u * r + 183u * g + 18u * b) >> 8u);
#else
    return (luat_color_t)0;
#endif
}

void luat_image_rgba_to_color_buffer(const uint8_t* rgba, uint32_t npx, luat_color_t* out) {
    for (uint32_t i = 0; i < npx; i++) {
        uint8_t r = rgba[i * 4 + 0];
        uint8_t g = rgba[i * 4 + 1];
        uint8_t b = rgba[i * 4 + 2];
        out[i] = luat_image_rgb_to_color(r, g, b);
    }
}
