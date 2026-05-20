#ifndef LUAT_IMAGE_COMMON_H
#define LUAT_IMAGE_COMMON_H

#include <stdint.h>

#include "luat_lcd.h"
#include "luat_image.h"

int luat_image_prepare_output(luat_img_info_t* img_info, uint16_t width, uint16_t height);
void luat_image_rgba_to_color_buffer(const uint8_t* rgba, uint32_t npx, luat_color_t* out);

#endif /* LUAT_IMAGE_COMMON_H */
