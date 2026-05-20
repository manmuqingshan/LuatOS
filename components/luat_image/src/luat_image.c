#include "luat_base.h"
#include "luat_image.h"
#include "luat_image_decoders_internal.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

static const luat_img_decoder_opts_t* const decoder_opts_table[] = {
#ifdef LUAT_USE_JPG
#ifdef LUAT_USE_TJPGD
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_JPG, LUAT_IMG_DECODE_SW)] = &jpeg_sw_decoder_opts,
#endif
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_JPG, LUAT_IMG_DECODE_HW)] = &jpeg_hw_decoder_opts,
#endif
#ifdef LUAT_USE_PNG
#ifdef LUAT_USE_LODEPNG
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_PNG, LUAT_IMG_DECODE_SW)] = &png_sw_decoder_opts,
#endif 
#ifdef LUAT_USE_PNG_HW
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_PNG, LUAT_IMG_DECODE_HW)] = &png_hw_decoder_opts,
#endif /* LUAT_USE_PNG_HW */
#endif /* LUAT_USE_PNG */
#ifdef LUAT_USE_WEBP
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_WEBP, LUAT_IMG_DECODE_SW)] = &webp_sw_decoder_opts,
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_WEBP, LUAT_IMG_DECODE_HW)] = &webp_hw_decoder_opts,
#endif
};

#define DECODER_OPTS_TABLE_SIZE (sizeof(decoder_opts_table) / sizeof(decoder_opts_table[0]))

const luat_img_decoder_opts_t* luat_image_get_decoder_opts(luat_img_format_t fmt, luat_img_decode_mode_t mode) {
    int key = LUAT_IMG_DECODER_KEY(fmt, mode);
    if (key < 0 || (size_t)key >= DECODER_OPTS_TABLE_SIZE) {
        return NULL;
    }
    return decoder_opts_table[key];
}

int luat_image_decode(luat_img_conf_t* img_conf, uint8_t *in_buf, size_t size, luat_img_info_t* img_info) {
    if (img_conf == NULL || in_buf == NULL || size == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    const luat_img_decoder_opts_t* opts = luat_image_get_decoder_opts(img_conf->format, img_conf->decode_mode);
    if (!opts || !opts->decode) {
        LLOGW("no decoder available for format=%d mode=%d", img_conf->format, img_conf->decode_mode);
        return LUAT_IMG_ERR;
    }
    return opts->decode(in_buf, size, img_info);
}
