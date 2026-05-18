#ifndef LUAT_IMAGE_DECODERS_INTERNAL_H
#define LUAT_IMAGE_DECODERS_INTERNAL_H

#include "luat_image.h"

#ifdef LUAT_USE_JPG
#ifdef LUAT_USE_TJPGD
extern const luat_img_decoder_opts_t jpeg_sw_decoder_opts;
#endif
extern const luat_img_decoder_opts_t jpeg_hw_decoder_opts;
#endif

#ifdef LUAT_USE_PNG
#ifdef LUAT_USE_LODEPNG
extern const luat_img_decoder_opts_t png_sw_decoder_opts;
#endif
extern const luat_img_decoder_opts_t png_hw_decoder_opts;
#endif

#ifdef LUAT_USE_WEBP
extern const luat_img_decoder_opts_t webp_sw_decoder_opts;
extern const luat_img_decoder_opts_t webp_hw_decoder_opts;
#endif

#endif /* LUAT_IMAGE_DECODERS_INTERNAL_H */
