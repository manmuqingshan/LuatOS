#include "luat_base.h"
#include "luat_image.h"
#include "luat_image_decoders_internal.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

/* ================================================================
 *  JPEG SW decoder — tjpgd
 *  Enabled by: LUAT_USE_TJPGD（JPEG SW 解码库开关，独立于 LUAT_USE_JPG）
 * ================================================================ */

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

typedef struct {
    const uint8_t *data;
    size_t len;
    size_t pos;
} mem_reader_t;

static unsigned int decode_mem_in_func(JDEC* jd, uint8_t* buff, unsigned int nbyte) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    mem_reader_t *reader = (mem_reader_t*)img_info->userdata;
    size_t available = reader->len - reader->pos;
    if ((size_t)nbyte > available) nbyte = (unsigned int)available;
    if (buff) {
        memcpy(buff, reader->data + reader->pos, nbyte);
    }
    reader->pos += nbyte;
    return nbyte;
}

static int decode_out_func(JDEC* jd, void* bitmap, JRECT* rect) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    luat_color_t *tmp = (luat_color_t*)bitmap;
    luat_color_t *out = (luat_color_t*)img_info->data;
    uint16_t idx = 0;
    for (size_t y = rect->top; y <= rect->bottom; y++) {
        size_t offset = (size_t)y * img_info->width + rect->left;
        for (size_t x = rect->left; x <= rect->right; x++) {
            out[offset] = tmp[idx];
            offset++; idx++;
        }
    }
    return 1;
}

int luat_jpeg_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    JRESULT res;
    JDEC jdec;
    void *work = NULL;
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3;
#else
    size_t sz_work = 3500;
#endif
    if (in_buf == NULL || in_len == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    mem_reader_t reader = {in_buf, in_len, 0};
    img_info->userdata = &reader;
    work = luat_heap_malloc(sz_work);
    if (work == NULL) {
        LLOGE("out of memory when malloc jpeg decode workbuff");
        goto error;
    }
    res = luat_jd_prepare(&jdec, decode_mem_in_func, work, sz_work, img_info);
    if (res != JDR_OK) {
        LLOGW("luat_jd_prepare mem error %d", res);
        goto error;
    }
    img_info->width  = jdec.width;
    img_info->height = jdec.height;
    img_info->size   = (uint32_t)jdec.width * jdec.height * sizeof(luat_color_t);
    img_info->data   = (uint8_t*)luat_heap_malloc(img_info->size);
    if (img_info->data == NULL) {
        LLOGE("out of memory when malloc jpeg image buff");
        goto error;
    }
    res = luat_jd_decomp(&jdec, decode_out_func, 0);
    if (res != JDR_OK) {
        LLOGW("luat_jd_decomp mem error %d", res);
        goto error;
    }
    luat_heap_free(work);
    return LUAT_IMG_OK;
error:
    if (work) luat_heap_free(work);
    if (img_info->data) {
        luat_heap_free(img_info->data);
        img_info->data = NULL;
    }
    return LUAT_IMG_ERR;
}

static int jpeg_sw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    return luat_jpeg_decode_sw_default(in_buf, in_len, img_info);
}
static const luat_img_decoder_opts_t jpeg_sw_decoder_opts = {
    .decode = jpeg_sw_decode_fn,
};
#endif /* LUAT_USE_TJPGD */


/* ================================================================
 *  PNG SW decoder — lodepng
 *  Enabled by: LUAT_USE_LODEPNG（PNG SW 解码库开关，独立于 LUAT_USE_PNG）
 * ================================================================ */

#ifdef LUAT_USE_LODEPNG
#include "lodepng.h"

int luat_png_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    unsigned char *rgba = NULL;
    unsigned w = 0, h = 0;
    unsigned err = lodepng_decode32(&rgba, &w, &h, in_buf, in_len);
    if (err) {
        LLOGE("lodepng decode error %u", err);
        return LUAT_IMG_ERR;
    }
    img_info->width  = (uint16_t)w;
    img_info->height = (uint16_t)h;
    img_info->size   = (uint32_t)w * h * sizeof(luat_color_t);
    img_info->data   = (uint8_t*)luat_heap_malloc(img_info->size);
    if (!img_info->data) {
        LLOGE("out of memory for png decode buffer");
        luat_heap_free(rgba);
        return LUAT_IMG_ERR;
    }

    luat_color_t *out = (luat_color_t*)img_info->data;
    uint32_t npx = (uint32_t)w * h;
    for (uint32_t i = 0; i < npx; i++) {
        uint8_t r = rgba[i * 4 + 0];
        uint8_t g = rgba[i * 4 + 1];
        uint8_t b = rgba[i * 4 + 2];
        /* alpha channel is currently ignored (composited against black) */
#if (LUAT_LCD_COLOR_DEPTH == 32)
        out[i] = (luat_color_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
#elif (LUAT_LCD_COLOR_DEPTH == 16)
        out[i] = (luat_color_t)(((luat_color_t)(r >> 3) << 11) |
                                 ((luat_color_t)(g >> 2) <<  5) |
                                  (luat_color_t)(b >> 3));
#elif (LUAT_LCD_COLOR_DEPTH == 8)
        /* BT.601 luma approximation */
        out[i] = (luat_color_t)((54u * r + 183u * g + 18u * b) >> 8u);
#endif
    }
    luat_heap_free(rgba);
    return LUAT_IMG_OK;
}

static int png_sw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    return luat_png_decode_sw_default(in_buf, in_len, img_info);
}
static const luat_img_decoder_opts_t png_sw_decoder_opts = {
    .decode = png_sw_decode_fn,
};
#endif /* LUAT_USE_LODEPNG */


/* ================================================================
 *  WebP SW decoder — libwebp
 *  Enabled by: LUAT_USE_WEBP
 * ================================================================ */

#ifdef LUAT_USE_WEBP
#include "webp/decode.h"

int luat_webp_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    int w = 0, h = 0;
    uint8_t *rgba = WebPDecodeRGBA(in_buf, in_len, &w, &h);
    if (!rgba) {
        LLOGE("WebPDecodeRGBA failed");
        return LUAT_IMG_ERR;
    }
    img_info->width  = (uint16_t)w;
    img_info->height = (uint16_t)h;
    img_info->size   = (uint32_t)w * h * sizeof(luat_color_t);
    img_info->data   = (uint8_t*)luat_heap_malloc(img_info->size);
    if (!img_info->data) {
        LLOGE("out of memory for webp decode buffer");
        WebPFree(rgba);
        return LUAT_IMG_ERR;
    }

    luat_color_t *out = (luat_color_t*)img_info->data;
    uint32_t npx = (uint32_t)w * h;
    for (uint32_t i = 0; i < npx; i++) {
        uint8_t r = rgba[i * 4 + 0];
        uint8_t g = rgba[i * 4 + 1];
        uint8_t b = rgba[i * 4 + 2];
        /* alpha channel is currently composited against black */
#if (LUAT_LCD_COLOR_DEPTH == 32)
        out[i] = (luat_color_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
#elif (LUAT_LCD_COLOR_DEPTH == 16)
        out[i] = (luat_color_t)(((luat_color_t)(r >> 3) << 11) |
                                 ((luat_color_t)(g >> 2) <<  5) |
                                  (luat_color_t)(b >> 3));
#elif (LUAT_LCD_COLOR_DEPTH == 8)
        out[i] = (luat_color_t)((54u * r + 183u * g + 18u * b) >> 8u);
#endif
    }
    WebPFree(rgba);
    return LUAT_IMG_OK;
}

static int webp_sw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    return luat_webp_decode_sw_default(in_buf, in_len, img_info);
}
static const luat_img_decoder_opts_t webp_sw_decoder_opts = {
    .decode = webp_sw_decode_fn,
};
#endif /* LUAT_USE_WEBP */


/* ================================================================
 *  HW decoder stubs — BSP platforms override via LUAT_WEAK
 *  Gated by LUAT_USE_JPG / LUAT_USE_PNG (高层格式开关)
 * ================================================================ */

#ifdef LUAT_USE_JPG
LUAT_WEAK int luat_jpeg_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)in_buf; (void)in_len; (void)img_info;
    return LUAT_IMG_ERR;
}
static int jpeg_hw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    LLOGI("jpeg hw decode: in_len=%u", (unsigned)in_len);
    int ret = luat_jpeg_decode_hw(in_buf, in_len, img_info);
    if (ret == LUAT_IMG_OK) {
        LLOGI("jpeg hw decoded: %dx%d, size=%u", img_info->width, img_info->height, (unsigned)img_info->size);
    }
    return ret;
}
static const luat_img_decoder_opts_t jpeg_hw_decoder_opts = {
    .decode = jpeg_hw_decode_fn,
};
#endif /* LUAT_USE_JPG */

#ifdef LUAT_USE_PNG_HW
LUAT_WEAK int luat_png_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)in_buf; (void)in_len; (void)img_info;
    return LUAT_IMG_ERR;
}
static int png_hw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    LLOGI("png hw decode: in_len=%u", (unsigned)in_len);
    return luat_png_decode_hw(in_buf, in_len, img_info);
}
static const luat_img_decoder_opts_t png_hw_decoder_opts = {
    .decode = png_hw_decode_fn,
};
#endif /* LUAT_USE_PNG_HW */

#ifdef LUAT_USE_WEBP
LUAT_WEAK int luat_webp_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)in_buf; (void)in_len; (void)img_info;
    return LUAT_IMG_ERR;
}
static int webp_hw_decode_fn(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    return luat_webp_decode_hw(in_buf, in_len, img_info);
}
static const luat_img_decoder_opts_t webp_hw_decoder_opts = {
    .decode = webp_hw_decode_fn,
};
#endif /* LUAT_USE_WEBP */


/* ================================================================
 *  Decoder opts table  (indexed by LUAT_IMG_DECODER_KEY)
 *
 *  Layout:
 *    [0]  LUAT_IMG_FMT_JPG  × LUAT_IMG_DECODE_SW
 *    [1]  LUAT_IMG_FMT_JPG  × LUAT_IMG_DECODE_HW
 *    [2]  LUAT_IMG_FMT_PNG  × LUAT_IMG_DECODE_SW
 *    [3]  LUAT_IMG_FMT_PNG  × LUAT_IMG_DECODE_HW
 *    [4]  LUAT_IMG_FMT_WEBP × LUAT_IMG_DECODE_SW
 *    [5]  LUAT_IMG_FMT_WEBP × LUAT_IMG_DECODE_HW
 * ================================================================ */

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
#endif
#endif
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
