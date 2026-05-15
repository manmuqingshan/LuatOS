#include "luat_audio_data_codec.h"
#include "luat_audio_define.h"
#include "luat_audio_driver.h"
#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_audio_request.h"
#include "luat_audio_channel.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_rtos_legacy.h"
#include <sys/_types.h>
#define LUAT_LOG_TAG "audio_core"
#include "luat_log.h"
#include "luat_gpio.h"

unsigned char luat_audio_debug_flag = 1;	// 调试标志位，默认1，开启调试
enum {
	LUAT_AUDIO_EV_TX_NEED_DATA = 0x01,
	LUAT_AUDIO_EV_TX_NO_DATA,
	LUAT_AUDIO_EV_RX_ENOUGH_DATA,
	LUAT_AUDIO_EV_REQUEST,

	LUAT_AUDIO_EV_TTS_RUN = 0x01,
};

typedef struct
{
	luat_llist_head request_block_list;
	luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_request_block_t *current_request_block; // 当前正在处理的请求块
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
	void *request_lock;	// 请求块列表操作保护锁
	void *tts_wait_sem;	// tts任务等待信号量
	uint32_t next_request_id;		// 下一个请求id
	uint8_t default_driver_index;	// 默认驱动索引
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

static __LUAT_C_CODE_IN_ISR__ void _audio_play_next_block(struct luat_audio_driver_ctrl *ctrl)
{
	volatile uint32_t next_play_cnt;
	ctrl->last_play_cnt = ctrl->current_play_cnt;
	ctrl->current_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	next_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	uint8_t *next_play_buff = ctrl->play_buff_byte + ctrl->one_play_block_len * next_play_cnt;
	if (!ctrl->data_channel->play_state) {	// 播放状态为停止，播放空白音
		ctrl->opts->fill(ctrl, next_play_buff, ctrl->one_play_block_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
		return;
	}
	// play数据从这里读取，只有1个消费者，所以不需要加锁
	uint32_t read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);

	if (read_len < ctrl->one_play_block_len) { 	// fifo没有完整的1个block
		ctrl->opts->fill(ctrl, next_play_buff + read_len, ctrl->one_play_block_len - read_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
	}
	if (!read_len) { // fifo没有数据，播放空白音
		if (ctrl->data_channel->blank_data_cnt < 10) { // 空数据计数
			ctrl->data_channel->blank_data_cnt++;
		}
	} else {
		ctrl->data_channel->blank_data_cnt = 0;
	}
	if (!_luat_audio.current_request_block) {  // 没有请求块，直接返回
		return;
	}
	if (luat_fifo_check_free_space(ctrl->data_channel->play_fifo) >= ctrl->data_channel->play_fifo_need_data_level) { // fifo剩余数据不足一半，需要请求更多数据
		luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_TX_NEED_DATA, (uint32_t)ctrl, 0, 0, 0);
	}
}

LUAT_WEAK __LUAT_C_CODE_IN_ISR__ void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl)
{
	uint32_t rest_data_len;
	switch (event) {
	case LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE:
		if (ctrl->opts->support_full_loop) {
			return;
		}
		_audio_play_next_block(ctrl);
		break;
	case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
		rest_data_len = luat_fifo_check_free_space(ctrl->data_channel->record_fifo);
		if (param < rest_data_len) {
			luat_fifo_write(ctrl->data_channel->record_fifo, rx_data, param);
		} else {
			ctrl->data_channel->error_record_overflow = 1;
		}
		if (luat_fifo_check_used_space(ctrl->data_channel->record_fifo) >= ctrl->data_channel->record_fifo_enough_data_level) {	// 录音数据足够，发送事件
			luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_RX_ENOUGH_DATA, (uint32_t)ctrl, 0, 0, 0);
		}
		if (ctrl->opts->support_full_loop) {
			_audio_play_next_block(ctrl);
		}
		break;
	default:
		break;
	}
}

static void _audio_find_next_request_block(void)
{
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		LLOGC(luat_audio_debug_flag, "no request block");
		return;
	}
	_luat_audio.current_request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
	luat_llist_del(&_luat_audio.current_request_block->node);
}


static int _audio_add_request(void *node, void *param)
{
	luat_audio_request_block_t *old_req = (luat_audio_request_block_t *)node;
	luat_audio_request_block_t *new_req = (luat_audio_request_block_t *)param;
	if (new_req->priority > old_req->priority)
	{
		LLOGC(luat_audio_debug_flag, "add request id %d priority %d before request id %d priority %d", new_req->request_id, new_req->priority, old_req->request_id, old_req->priority);
		luat_llist_add_tail(&new_req->node, &old_req->node);
		return LUAT_LIST_FIND;
	}
	return LUAT_LIST_PASS;
}

static int _audio_tts_output_callback(void *data, uint32_t param, void *user_data)
{
	luat_audio_request_block_t *request_block = (luat_audio_request_block_t *)user_data;
	int ret;
	if (data) {
		while(!request_block->is_user_stop && luat_fifo_check_free_space(request_block->data_channel->play_fifo) >= request_block->codec.opts->decode_max_output_len * ((request_block->data_channel->driver_ctrl->common_param.data_align == 3)?4:request_block->data_channel->driver_ctrl->common_param.data_align))
		{
			LLOGC(luat_audio_debug_flag, "tts wait fifo space %d", luat_fifo_check_free_space(request_block->data_channel->play_fifo));
			if (luat_rtos_semaphore_take(_luat_audio.tts_wait_sem, 1000)) {
				LLOGE("tts wait timeout");
				return -1;
			}
		}
		if (request_block->is_user_stop) {
			LLOGC(luat_audio_debug_flag, "tts user stop, stop");
			return -1;
		}
		uint32_t written_bytes = 0;
		ret = luat_audio_channel_write_data(request_block->data_channel, data, param, &written_bytes, request_block->codec.common_param.is_signed, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);		
		if (ret) {
			LLOGE("tts write data failed");
			return -1;
		}
	} else {
		ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->codec.common_param, request_block->play_buff, request_block->one_block_len, request_block->block_nums);
		if (ret) {
			LLOGE("tts start driver failed");
			return -1;
		}
	}
	return LUAT_ERROR_NONE;
}

static void luat_audio_tts_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *tts_request_block;
	for(;;)
	{
		luat_rtos_event_recv(_luat_audio.tts_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TTS_RUN:
			tts_request_block = (luat_audio_request_block_t *)out_event.param1;
			if (tts_request_block->request_id == _luat_audio.current_request_block->request_id) {
				tts_request_block->codec.param.tts_output_callback_t = _audio_tts_output_callback;
				if (tts_request_block->codec.opts->tts_decode(&tts_request_block->codec, tts_request_block->tts_data, tts_request_block->tts_data_size, tts_request_block)) {
					tts_request_block->is_error_stop = 1;
				}
			}
			break;
		default:
			break;
		}
	}
}

static int _audio_data_open(luat_audio_decode_file_info_t *decode_file)
{
	if (decode_file->file_info->path) {
		decode_file->fd = luat_fs_fopen(decode_file->file_info->path, "r");
		if (!decode_file->fd) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
	} else {
		decode_file->rom_data_offset = 0;
	}
	return -LUAT_ERROR_NONE;
}

static int _audio_data_read_to_fifo(luat_audio_decode_file_info_t *decode_file, luat_fifo_t *input_data_fifo, uint32_t need_len)
{
    if (luat_fifo_check_free_space(input_data_fifo) < need_len) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    uint32_t done_len = 0;
    uint32_t read_len;
    if (decode_file->fd) {
        uint8_t temp[1024];

        int ret;
        while (done_len < need_len) {
            read_len = ((need_len - done_len) > sizeof(temp))? sizeof(temp) : (need_len - done_len);
            ret = luat_fs_fread(temp, read_len, 1, decode_file->fd);
            if (ret < 0) {
                return -LUAT_ERROR_OPERATION_FAILED;
            } else {
                done_len += ret;
                if (ret) {
                    luat_fifo_write(input_data_fifo, temp, ret);
                }
                if (ret < read_len) {
                    break;
                }
            }
        }
        return done_len;
    } else {
        read_len = ((decode_file->file_info->rom_data_len - decode_file->rom_data_offset) > need_len) ? need_len : (decode_file->file_info->rom_data_len - decode_file->rom_data_offset);
        luat_fifo_write(input_data_fifo, decode_file->file_info->rom_data + decode_file->rom_data_offset, read_len);
        decode_file->rom_data_offset += read_len;
        return read_len;
    }
}

static int _audio_data_read_to_buffer(luat_audio_decode_file_info_t *decode_file, uint8_t *buffer, uint32_t need_len)
{
    if (decode_file->fd) {
		return luat_fs_fread(buffer, need_len, 1, decode_file->fd);
    } else {
        uint32_t read_len = ((decode_file->file_info->rom_data_len - decode_file->rom_data_offset) > need_len) ? need_len : (decode_file->file_info->rom_data_len - decode_file->rom_data_offset);
		memcpy(buffer, decode_file->file_info->rom_data + decode_file->rom_data_offset, read_len);
        decode_file->rom_data_offset += read_len;
        return read_len;
    }
}

static int _audio_data_seek(luat_audio_decode_file_info_t *decode_file, int offset, int origin)
{
    if (decode_file->fd) {
        return luat_fs_fseek(decode_file->fd, offset, origin);
    } else {
		switch(origin)
		{
		case SEEK_SET:
			if (offset < decode_file->file_info->rom_data_len) {
				decode_file->rom_data_offset = offset;
			} else {
				decode_file->rom_data_offset = decode_file->file_info->rom_data_len;
			}
			break;
		case SEEK_CUR:
			if ((offset + decode_file->rom_data_offset) < decode_file->file_info->rom_data_len) {
				decode_file->rom_data_offset += offset;
			} else {
				decode_file->rom_data_offset = offset;
			}
			break;
		case SEEK_END:
			decode_file->rom_data_offset = decode_file->file_info->rom_data_len - offset;
			break;
		}
		return decode_file->rom_data_offset;
    }
}

static int _audio_data_close(luat_audio_decode_file_info_t *decode_file)
{
	if (decode_file->fd)
	{
		if (luat_fs_fclose(decode_file->fd)) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
        decode_file->fd = NULL;
		return LUAT_ERROR_NONE;
	}
	else
	{
        decode_file->rom_data_offset = 0;
		return LUAT_ERROR_NONE;
	}
}

static int _audio_decode_current_request(luat_audio_request_block_t *request_block)
{
	if (request_block->codec.opts) {
		//已经指定了解码器则自动处理
		if (luat_audio_get_play_info_from_file(&request_block->codec, &request_block->decode_file)) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		LLOGC(luat_audio_debug_flag, "find play info %u,%u,%u", request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);
		return LUAT_ERROR_NONE;
	}
	else {
		uint8_t codec_type = 255;
		//没有指定解码器则需要搜索所有的解码器，解码尝试分析播放参数，找到合适的解码器
		for (int i = 0; i < LUAT_AUDIO_DATA_CODEC_TYPE_MAX; i++) {
			request_block->codec.opts = (luat_audio_data_codec_opts_t *)luat_audio_data_codec_find(i);
			if (LUAT_ERROR_NONE == luat_audio_get_play_info_from_file(&request_block->codec, &request_block->decode_file)) {
				LLOGC(luat_audio_debug_flag, "auto search find codec %d", i);
				codec_type = i;
				break;
			}
		}
		if (255 == codec_type) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		LLOGC(luat_audio_debug_flag, "find play info %u,%u,%u", request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);
		return luat_audio_data_codec_bind(&request_block->codec, luat_audio_data_codec_find(codec_type), request_block);
	}
}

static int _audio_decode_file_start(luat_audio_request_block_t *request_block)
{
	luat_audio_play_file_info_t *file_info = &request_block->file_info[request_block->file_done_cnt];
	if (request_block->decode_file.fd) {
		luat_fs_fclose(request_block->decode_file.fd);
	}
	memset(&request_block->decode_file, 0, sizeof(luat_audio_decode_file_info_t));
	request_block->decode_file.file_info = file_info;
	if (_audio_data_open(&request_block->decode_file)) {
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (_audio_decode_current_request(request_block)) {
		_audio_data_close(&request_block->decode_file);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	return LUAT_ERROR_NONE;
}

static int _audio_start_request(luat_audio_request_block_t *request_block)
{
	int ret;
	// 再根据请求块的模式设置录音fifo的enough_data_level
	if (LUAT_AUDIO_DRIVER_MODE_RECORD == request_block->driver_work_mode) {
		request_block->data_channel->record_fifo_enough_data_level = request_block->record_fifo_enough_data_level;
	} else {
		request_block->data_channel->record_fifo_enough_data_level = request_block->one_block_len;
	}

	request_block->cb(LUAT_AUDIO_REQUEST_EVENT_START, NULL, 0, request_block->user_data);
	// 最后根据请求块的模式做不同的解码操作
	if (request_block->is_tts) {	//TTS模式发送给tts_task处理
		luat_rtos_event_send(_luat_audio.tts_task_handle, LUAT_AUDIO_EV_TTS_RUN, request_block, 0, 0, 0);
		return LUAT_ERROR_NONE;
	} else if (!request_block->is_stream) {	//本地文件模式
		if (_audio_decode_file_start(request_block)) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
	}

	ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, request_block->driver_work_mode, request_block->play_buff, request_block->one_block_len, request_block->block_nums);
	if (ret) {
		LLOGE("request id %d start driver failed, ret %d", request_block->request_id, ret);
		request_block->is_error_stop = 1;
		luat_llist_del(&request_block->node);
		luat_audio_request_deinit(request_block);
		request_block->cb(LUAT_AUDIO_REQUEST_EVENT_END, NULL, 0, request_block->user_data);
		return ret;
	}
	return LUAT_ERROR_NONE;
}

static void luat_audio_common_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *request_block;
	uint8_t request_change;
	for(;;) {
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TX_NEED_DATA:
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {
				luat_mutex_unlock(_luat_audio.request_lock);
				luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
				break;
			}
			request_block = _luat_audio.current_request_block;
			luat_mutex_unlock(_luat_audio.request_lock);
			if (request_block->is_stream) {	//流媒体模式
				if (request_block->codec.opts) { //已经指定了解码器则自动处理
					luat_audio_data_codec_decode_once(&request_block->codec, 
						request_block->input_data_fifo, 
						&request_block->out_buffer, 
						request_block->is_stream_end);
					if (request_block->out_buffer.pos) {
						uint32_t written_bytes = 0;
						luat_audio_channel_write_data(request_block->data_channel, request_block->out_buffer.data, request_block->out_buffer.pos, &written_bytes, request_block->codec.common_param.is_signed, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);
						request_block->out_buffer.pos -= written_bytes;
					} else {
						request_block->out_buffer.pos = 0;
					}
				}
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA, NULL, 0, request_block->user_data);
			} else {
				if (request_block->is_tts) {
					luat_mutex_unlock(_luat_audio.tts_wait_sem);
				} else {
					//加入解码文件写入fifo
				}
			}
			
			break;
		case LUAT_AUDIO_EV_RX_ENOUGH_DATA:
			request_block = _luat_audio.current_request_block;
			if (request_block) {
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA, NULL, 0, request_block->user_data);
			}
			break;
		case LUAT_AUDIO_EV_REQUEST:
			request_change = 0;
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {	// 没有请求块，找下一个请求块
				_audio_find_next_request_block();
				if (!_luat_audio.current_request_block) {	// 找不到请求块，直接返回
					luat_mutex_unlock(_luat_audio.request_lock);
					break;
				}
				request_change = 1;
			} else {	// 有请求块，检查一下队列里是否有更高优先级的请求块
				if (!luat_llist_empty(&_luat_audio.request_block_list)) { // 请求队列不空的情况下，检查一下是否有更高优先级的请求块
					request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
					if (request_block->priority > _luat_audio.current_request_block->priority) {
						LLOGD("request_id: %d priority higher than now request_id: %d", request_block->request_id, _luat_audio.current_request_block->request_id);
						luat_llist_del(&request_block->node);
						if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, _luat_audio.current_request_block)) {
							luat_llist_add_tail(&_luat_audio.current_request_block->node, &_luat_audio.request_block_list)	;
						}
						_luat_audio.current_request_block = request_block;
						request_change = 1;
					}
				}
				luat_mutex_unlock(_luat_audio.request_lock);
			}
			if (request_change) {
				// 请求块有变化，需要重新播放
				if (_audio_start_request(_luat_audio.current_request_block)) {	// 启动请求块失败，将当前工作请求块设置为NULL，并且重新触发一下请求事件
					_luat_audio.current_request_block = NULL;
					luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
				}
			}
			break;
		}
	}
}

int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, struct luat_audio_driver_probe probe, void *driver_data)
{
	int i;
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts == NULL) {
			_luat_audio.driver_ctrl[i].opts = opts;
			_luat_audio.driver_ctrl[i].driver_data = driver_data;
			_luat_audio.driver_ctrl[i].probe = probe;
			_luat_audio.driver_ctrl[i].data_channel = &_luat_audio.channel[i];
			if (opts->init(&_luat_audio.driver_ctrl[i])) {
				LLOGE("%d-%d driver init failed, can not register", probe.bus_type, probe.bus_id);
				memset(&_luat_audio.driver_ctrl[i], 0, sizeof(luat_audio_driver_ctrl_t));
				return -LUAT_ERROR_OPERATION_FAILED; // 驱动注册失败，初始化失败
			}
			_luat_audio.driver_ctrl[i].state = LUAT_AUDIO_DRIVER_STATE_INITED;
			_luat_audio.channel[i].driver_ctrl = &_luat_audio.driver_ctrl[i];
			_luat_audio.channel[i].play_lock_mutex = luat_mutex_create();
			_luat_audio.channel[i].soft_vol = 100;
			return LUAT_ERROR_NONE;
		}
	}
	LLOGE("driver register failed, max driver count is %d", LUAT_AUDIO_DRIVER_MAX);
	return -LUAT_ERROR_ID_INVALID; // 驱动注册失败，超过最大支持数量
}

luat_audio_driver_ctrl_t *luat_audio_driver_probe(luat_audio_driver_probe_t *probe)
{
	int i;
	if (!probe) {
		if (_luat_audio.driver_ctrl[_luat_audio.default_driver_index].opts) {
			LLOGC(luat_audio_debug_flag, "use default driver index: %d %d-%d", _luat_audio.default_driver_index,
				_luat_audio.driver_ctrl[_luat_audio.default_driver_index].probe.bus_type,
				_luat_audio.driver_ctrl[_luat_audio.default_driver_index].probe.bus_id);
			return &_luat_audio.driver_ctrl[_luat_audio.default_driver_index];
		}
		return NULL;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.bus_type == probe->bus_type && _luat_audio.driver_ctrl[i].probe.bus_id == probe->bus_id) {
			return &_luat_audio.driver_ctrl[i];
		}
	}
	return NULL;
}

int luat_audio_driver_set_default(luat_audio_driver_probe_t *probe)
{
	int i;
	if (!probe) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.bus_type == probe->bus_type && _luat_audio.driver_ctrl[i].probe.bus_id == probe->bus_id) {
			_luat_audio.default_driver_index = i;
			return LUAT_ERROR_NONE;
		}
	}
	return -LUAT_ERROR_PARAM_INVALID;
}

int luat_audio_request_init(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	memset(req, 0, sizeof(luat_audio_request_block_t));
	luat_mutex_lock(_luat_audio.request_lock);
	req->request_id = ++_luat_audio.next_request_id;
	luat_mutex_unlock(_luat_audio.request_lock);
	return LUAT_ERROR_NONE;
}

void luat_audio_request_deinit(luat_audio_request_block_t *req)
{
	if (!req) {
		return;
	}
	if (req->decode_file.fd) {
		luat_fs_fclose(req->decode_file.fd);	
		req->decode_file.fd = NULL;
	}
	luat_heap_free(req->input_data_fifo);
	req->input_data_fifo = NULL;
	luat_buffer_deinit(&req->out_buffer);
	luat_audio_data_codec_deinit(&req->codec);
	req->file_info = NULL;
	req->tts_data = NULL;
	LLOGC(luat_audio_debug_flag, "request_id: %d deinit", req->request_id);
}

int luat_audio_request_start(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d add in request_block_list", req->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_llist_add(&req->node, &_luat_audio.request_block_list);
	} else {
		if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, req)) {
			luat_llist_add_tail(&req->node, &_luat_audio.request_block_list);
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

int luat_audio_request_cancel(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d cancel", req->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	luat_llist_del(&req->node);
	if (_luat_audio.current_request_block) {
		if (req->request_id == _luat_audio.current_request_block->request_id) {
			LLOGC(luat_audio_debug_flag, "now work request_id: %d cancel", req->request_id);
			_luat_audio.current_request_block = NULL;
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

int luat_audio_request_prepare(luat_audio_request_block_t *req, luat_audio_driver_probe_t *probe, uint8_t driver_work_mode, 
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	luat_audio_request_init(req);
	luat_audio_driver_ctrl_t *driver_ctrl = luat_audio_driver_probe(probe);
	if (!driver_ctrl) {
		return -LUAT_ERROR_NO_SUCH_ID;
	}
	req->data_channel = driver_ctrl->data_channel;
	req->driver_work_mode = driver_work_mode;
	req->cb = cb;
	req->user_data = user_data;
	return LUAT_ERROR_NONE;
}

int luat_audio_request_play_files(luat_audio_request_block_t *req, luat_audio_driver_probe_t *probe, luat_audio_play_file_info_t *files, uint32_t files_num, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret =luat_audio_request_prepare(req, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	void *done_sem = NULL;
	if (is_sync) {
		done_sem = luat_mutex_create();
		luat_mutex_lock(done_sem);
	} 
	req->done_sem = done_sem;
	req->priority = priority;
	req->file_info = files;
	req->file_info_cnt = files_num;
	ret = luat_audio_request_start(req);
	if (ret != LUAT_ERROR_NONE) {
		if (is_sync) {
			luat_mutex_release(done_sem);
		}
		req->is_error_stop = 1;
		return ret;
	}

	if (is_sync) {
		luat_mutex_lock(done_sem);
		luat_mutex_release(done_sem);
		if (req->is_error_stop) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
	}

	return LUAT_ERROR_NONE;
}

int luat_audio_request_play_tts(luat_audio_request_block_t *req, luat_audio_driver_probe_t *probe, const char *text, uint32_t text_len, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(req, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	void *done_sem = NULL;
	req->priority = priority;
	if (is_sync) {
		done_sem = luat_mutex_create();
		luat_mutex_lock(done_sem);
	}
	req->done_sem = done_sem;
	req->tts_data = text;
	req->tts_data_size = text_len;
	ret = luat_audio_request_start(req);
	if (is_sync) {
		luat_mutex_lock(done_sem);
		luat_mutex_release(done_sem);
		if (req->is_error_stop) {
			return -LUAT_ERROR_OPERATION_FAILED;
		}
	}
	return LUAT_ERROR_NONE;
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 90, "luat_audio", luat_audio_common_task, NULL, 64);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.request_lock = luat_mutex_create();
	_luat_audio.tts_wait_sem = luat_mutex_create();
	luat_mutex_lock(_luat_audio.tts_wait_sem);
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
}

void luat_audio_debug_switch(uint8_t on_off)
{
	luat_audio_debug_flag = on_off;
}

int luat_audio_get_play_info_from_file(luat_audio_data_codec_t *codec, luat_audio_decode_file_info_t *decode_file)
{
    if (!codec || !decode_file) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int read_len;
    luat_buffer_t input_buffer;
    uint8_t temp[12];
    uint32_t jump_offset_bytes = 0;
    uint32_t need_bytes = 0;
	_audio_data_seek(decode_file, 0, SEEK_SET);
    input_buffer.data = temp;
    input_buffer.pos = 0;
    input_buffer.max_len = sizeof(temp);
    codec->common_param.sample_rate = 0;
    read_len = _audio_data_read_to_buffer(decode_file, input_buffer.data, input_buffer.max_len);
    if (read_len != sizeof(temp)) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    input_buffer.pos = read_len;
    int ret =codec->opts->get_play_info(codec, &input_buffer, &jump_offset_bytes, &need_bytes, &codec->common_param);
    if (ret) {
        return ret;
    }
    memset(&input_buffer, 0, sizeof(input_buffer));
    uint8_t retry_count = 0;
    while (!codec->common_param.sample_rate && retry_count < 5) {
        _audio_data_seek(decode_file, jump_offset_bytes, SEEK_SET);
        luat_buffer_reinit(&input_buffer, need_bytes);
        read_len = _audio_data_read_to_buffer(decode_file, input_buffer.data, input_buffer.max_len);
        if (read_len != need_bytes) {
            return -LUAT_ERROR_OPERATION_FAILED;
        }
        input_buffer.pos = read_len;
        jump_offset_bytes = 0;
        need_bytes = 0;
        ret =codec->opts->get_play_info(codec, &input_buffer, &jump_offset_bytes, &need_bytes, &codec->common_param);
        if (ret) {
            return ret;
        }
        retry_count++;
    }
    if (!codec->common_param.sample_rate) {
        LLOGE("get common param failed, retry %d times", retry_count);
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    _audio_data_seek(decode_file, jump_offset_bytes, SEEK_SET);
    return LUAT_ERROR_NONE;
}