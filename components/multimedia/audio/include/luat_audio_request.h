#ifndef __LUAT_AUDIO_REQUEST__
#define __LUAT_AUDIO_REQUEST__

/**
 * @file luat_audio_request.h
 * @brief LuatOS 音频请求块定义头文件
 * 
 * 定义音频播放/录音请求的数据结构，包含文件句柄、编解码器、DSP处理等信息。
 * 
 * @defgroup luat_audio_request 音频请求模块
 * @ingroup audio
 * @{
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_common_api.h"
#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_dsp.h"
#include "luat_audio_driver.h"
#include "luat_fs.h"

typedef struct
{
	char *path;		//文件路径，如果为NULL，则表示是ROM数组
	uint32_t address;	//ROM数组地址
	uint32_t rom_data_len;	//ROM数组长度
	uint32_t fail_continue;	//如果解码失败是否跳过继续下一个，如果是最后一个文件，强制停止并设置错误信息
}luat_audio_play_file_info_t;

typedef void (*luat_audio_request_cb_t)(uint32_t request_id, uint8_t is_stream_end);
/**
 * @brief 音频请求块结构
 * 
 * 表示一个音频播放或录音请求，包含所有必要的上下文信息。
 * 请求块通过链表节点组织，可以支持多个并发请求的排队和管理。
 */
struct luat_audio_request_block {
    luat_llist_head node;                       /**< 链表节点，用于请求队列管理 */
    uint32_t request_id;                       /**< 请求ID，用于标识请求 */
    luat_audio_request_cb_t cb;                 /**< 请求回调函数 */
    void *user_data;                           /**< 用户数据指针，用于传递自定义数据 */
    luat_audio_play_file_info_t *file_info;     /**< 音频文件信息 */
    void *tts_data;                             /**< 文本转语音数据指针 */
    uint32_t tts_data_size_or_file_info_cnt;    /**< 文本转语音数据大小或文件信息数量，根据fail_continue判断 */
    uint32_t file_info_done_cnt;                /**< 已处理的文件信息数量 */
    FILE *fd;                                /**< 音频文件句柄 */
    luat_fifo_t *input_data_fifo;            /**< 输入数据FIFO缓冲区 */
    luat_buffer_t out_buffer;                /**< 输出数据缓冲区 */
    luat_audio_dsp_t *dsp;                  /**< 关联的DSP处理实例 */
    luat_audio_data_codec_t codec;          /**< 关联的编解码器实例 */
    luat_audio_channel_t *data_channel;      /**< 关联的音频通道 */
    //uint8_t decode_state;                    /**< 解码状态 */
    uint8_t is_stream;                       /**< 是否为流式请求 */
    uint8_t is_stream_end;                   /**< 是否为流式请求结束 */
    uint8_t user_stop;                       /**< 用户是否请求停止 */
    uint8_t priority;                        /**< 请求优先级 (0-255)，数值越大优先级越高 */
};

typedef struct luat_audio_request_block luat_audio_request_block_t;

/**
 * @brief 播放音频文件
 * 
 * 此函数用于播放音频文件，支持指定文件路径和播放参数。
 * 
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则使用默认驱动。
 * @param files 音频文件路径数组指针，每个元素为一个音频文件路径
 * @param files_num 音频文件路径数组的元素数量
 * @param error_stop 是否在播放错误时停止播放，0 表示继续播放，1 表示停止播放
 * @param priority 请求优先级，0-255，数值越大优先级越高
 * @param cb 请求回调函数，用于在播放完成或错误时通知应用层
 * @param user_data 用户数据指针，用于传递自定义数据
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_request_play_files(luat_audio_driver_probe_t *probe, luat_audio_play_file_info_t *files, uint32_t files_num, 
    uint8_t error_stop, uint8_t priority, 
    luat_audio_request_cb_t cb, void *user_data);

/**
* @brief 播放文本转语音
* 
* 
* @param req 音频请求块指针，用于存储播放参数
* @param text 要转换为文本的指针
* @param text_len 文本长度
* @param priority 请求优先级，0-255，数值越大优先级越高
* @param cb 请求回调函数，用于在播放完成或错误时通知应用层
* @param user_data 用户数据指针，用于传递自定义数据
* @return 0 表示成功，其他值表示失败
*/
int luat_audio_request_play_tts(luat_audio_driver_probe_t *probe, const char *text, uint32_t text_len, uint8_t priority, 
    luat_audio_request_cb_t cb, void *user_data);
#endif

/** @} */
