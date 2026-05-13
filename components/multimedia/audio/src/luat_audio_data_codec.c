#include "luat_audio_data_codec.h"
#include "luat_audio_define.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "audio_codec"
#include "luat_log.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

typedef struct {
    const luat_audio_data_codec_opts_t *opts;
    uint8_t is_busy;
}luat_audio_data_codec_item_t;

static luat_audio_data_codec_item_t _audio_data_codec_software_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];
static luat_audio_data_codec_item_t _audio_data_codec_hardware_items[LUAT_AUDIO_DATA_CODEC_TYPE_MAX];

int luat_audio_data_codec_bind(luat_audio_data_codec_t *codec, const luat_audio_data_codec_opts_t *opts, void *user_data)
{
    if (!codec || !opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    memset(codec, 0, sizeof(luat_audio_data_codec_t));
    if (!opts->is_reentrant && opts->is_hardware) {
        if (_audio_data_codec_hardware_items[opts->type].is_busy) {
            return -LUAT_ERROR_DEVICE_BUSY;
        }
        else {
            _audio_data_codec_hardware_items[opts->type].is_busy = 1;
            LLOGC(luat_audio_debug_flag, "bind hardware data codec %d, now device is busy", opts->type);
        }
    }
    // 初始化编解码器上下文
    codec->input_buffer = luat_heap_malloc(opts->decode_min_input_len);
    if (!codec->input_buffer) {
        return -LUAT_ERROR_NO_MEMORY;
    }
    codec->opts = opts;
    
    codec->user_data = user_data;
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_init(luat_audio_data_codec_t *codec, luat_audio_data_codec_param_u *param)
{
    if (!codec || !param) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (codec->codec_ctx) {
        return -LUAT_ERROR_DEVICE_BUSY;
    }
    codec->param = *param;
    codec->codec_ctx = codec->opts->create(codec);
    if (!codec->codec_ctx) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_deinit(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_heap_free(codec->input_buffer);
    codec->input_buffer = NULL;
    if (codec->codec_ctx) {
        codec->opts->destroy(codec);
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_unbind(luat_audio_data_codec_t *codec)
{
    if (!codec) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (codec->opts->is_hardware) {
        _audio_data_codec_hardware_items[codec->opts->type].is_busy = 0;
    }
    else {
        _audio_data_codec_software_items[codec->opts->type].is_busy = 0;
    }
    codec->opts = NULL;
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_decode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer, uint8_t is_end)
{
    if (!codec || !input_data_fifo || !output_data_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t input_data_len = 0;
    uint32_t out_len, used_len;
    int ret;
    while ((output_data_buffer->pos + codec->opts->decode_max_output_len) <= output_data_buffer->max_len) {
        if (luat_fifo_check_used_space(input_data_fifo) < codec->opts->decode_min_input_len) {
            if (is_end) {   // 最后一次解码，读取所有数据
                input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
            } else {
                // 非最后一次解码，返回0
                return LUAT_ERROR_NONE;
            }
        } else {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->decode_min_input_len);
        }
        // 使用codec解码数据
        ret = codec->opts->decode(codec, &codec->play_info, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &out_len, &used_len);
        luat_fifo_delete(input_data_fifo, used_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
        }
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_encode_once(luat_audio_data_codec_t *codec, luat_fifo_t *input_data_fifo, luat_buffer_t *output_data_buffer)
{
    if (!codec || !input_data_fifo || !output_data_buffer) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t input_data_len = 0;
    uint32_t out_len;
    int ret;
    while ((output_data_buffer->pos + codec->opts->encode_max_output_len) <= output_data_buffer->max_len) {
        if (luat_fifo_check_used_space(input_data_fifo) >= codec->opts->encode_min_input_len) {
            input_data_len = luat_fifo_query(input_data_fifo, codec->input_buffer, codec->opts->encode_min_input_len);
        } else {
            return LUAT_ERROR_NONE;
        }
        // 使用codec编码数据
        ret = codec->opts->encode(codec, &codec->play_info, codec->input_buffer, input_data_len,
                                                        output_data_buffer->data + output_data_buffer->pos, 
                                &out_len);
        luat_fifo_delete(input_data_fifo, input_data_len);
        if (!ret) {
            output_data_buffer->pos += out_len;
        } else {
            LLOGE("encode failed, ret = %d", ret);
        }
    }
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t* luat_audio_data_codec_find(uint8_t type)
{
    if (type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (_audio_data_codec_hardware_items[type].opts) {
        return _audio_data_codec_hardware_items[type].opts;
    }
    if (_audio_data_codec_software_items[type].opts) {
        return _audio_data_codec_software_items[type].opts;
    }
    return NULL;
}

int luat_audio_data_codec_register(const luat_audio_data_codec_opts_t *opts)
{
    if (!opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (opts->type >= LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        LLOGE("type %d unknown can not register in data codec", opts->type);
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (opts->is_hardware) {
        _audio_data_codec_hardware_items[opts->type].opts = opts;
    }
    else {
        _audio_data_codec_software_items[opts->type].opts = opts;
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_data_codec_get_play_info_from_file(luat_audio_data_codec_t *codec, FILE* fd)
{
    if (!codec || !fd) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int read_len;
    luat_buffer_t input_buffer;
    uint8_t temp[12];
    uint32_t jump_offset_bytes = 0;
    uint32_t need_bytes = 0;
    luat_fs_fseek(fd, 0, SEEK_SET);
    input_buffer.data = temp;
    input_buffer.pos = 0;
    input_buffer.max_len = sizeof(temp);
    codec->play_info.sample_rate = 0;
    read_len = luat_fs_fread(input_buffer.data, input_buffer.max_len, 1, fd);
    if (read_len != sizeof(temp)) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    input_buffer.pos = read_len;
    int ret =codec->opts->get_play_info(codec, &input_buffer, &jump_offset_bytes, &need_bytes, &codec->play_info);
    if (ret) {
        return ret;
    }
    memset(&input_buffer, 0, sizeof(input_buffer));
    uint8_t retry_count = 0;
    while (!codec->play_info.sample_rate && retry_count < 5) {
        luat_fs_fseek(fd, jump_offset_bytes, SEEK_SET);
        luat_buffer_reinit(&input_buffer, need_bytes);
        read_len = luat_fs_fread(input_buffer.data, input_buffer.max_len, 1, fd);
        if (read_len != need_bytes) {
            return -LUAT_ERROR_OPERATION_FAILED;
        }
        input_buffer.pos = read_len;
        jump_offset_bytes = 0;
        need_bytes = 0;
        ret =codec->opts->get_play_info(codec, &input_buffer, &jump_offset_bytes, &need_bytes, &codec->play_info);
        if (ret) {
            return ret;
        }
        retry_count++;
    }
    if (!codec->play_info.sample_rate) {
        LLOGE("get play info failed, retry %d times", retry_count);
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    luat_fs_fseek(fd, jump_offset_bytes, SEEK_SET);
    return LUAT_ERROR_NONE;
}