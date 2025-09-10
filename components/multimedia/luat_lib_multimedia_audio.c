
/*
@module  audio
@summary 多媒体-音频
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_MEDIA
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "audio"
#include "luat_log.h"

#include "luat_multimedia.h"
#include "luat_audio.h"
#include "luat_mem.h"
#define MAX_DEVICE_COUNT 2
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#ifdef LUAT_USE_RECORD
static luat_record_ctrl_t g_s_record = {0};
#endif
static luat_multimedia_cb_t multimedia_cbs[MAX_DEVICE_COUNT];

int l_multimedia_raw_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (multimedia_cbs[msg->arg2].function_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, multimedia_cbs[msg->arg2].function_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg2);
            lua_pushinteger(L, msg->arg1);
#ifdef LUAT_USE_RECORD
            if (msg->arg1 == LUAT_MULTIMEDIA_CB_RECORD_DATA){
            	lua_pushinteger(L, (int)msg->ptr);
                lua_call(L, 3, 0);
            }else{
                lua_call(L, 2, 0);
            }
#else
            lua_call(L, 2, 0);
#endif
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
启动一个多媒体通道准备播放音频
@api audio.start(id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed)
@int 多媒体播放通道号
@int 音频格式
@int 声音通道数
@int 采样频率
@int 采样位数
@boolean 是否有符号，默认true
@return boolean 成功true, 失败false
@usage
audio.start(0, audio.PCM, 1, 16000, 16)
*/
static int l_audio_start_raw(lua_State *L){
	int multimedia_id = luaL_checkinteger(L, 1);
	int audio_format = luaL_checkinteger(L, 2);
	int num_channels= luaL_checkinteger(L, 3);
	int sample_rate = luaL_checkinteger(L, 4);
	int bits_per_sample = luaL_checkinteger(L, 5);
	int is_signed = 1;
	if (lua_isboolean(L, 6))
	{
		is_signed = lua_toboolean(L, 6);
	}
	lua_pushboolean(L, !luat_audio_start_raw(multimedia_id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed));
    return 1;
}

#ifdef LUAT_USE_RECORD

#ifdef LUAT_SUPPORT_AMR
#include "interf_enc.h"
#include "interf_dec.h"
#endif
#include "luat_fs.h"
#define RECORD_ONCE_LEN	5


#ifdef LUAT_SUPPORT_AMR
static void record_encode_amr(uint8_t *data, uint32_t len){
	uint8_t outbuf[64];
	int16_t *pcm = (int16_t *)data;
	uint32_t total_len = len >> 1;
	uint32_t done_len = 0;
	uint8_t out_len;
	uint32_t pcm_len = (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)?160:320;
	while ((total_len - done_len) >= pcm_len){
#ifdef LUAT_USE_INTER_AMR
		luat_audio_inter_amr_coder_encode(g_s_record.encoder_handler, &pcm[done_len], outbuf,&out_len);
#else
        out_len = Encoder_Interface_Encode(g_s_record.encoder_handler, g_s_record.quailty , &pcm[done_len], outbuf, 0);
#endif
		if (out_len <= 0){
			LLOGD("encode error in %d,result %d", done_len, out_len);
		}else{
            luat_fs_fwrite(outbuf, out_len, 1, g_s_record.fd);
		}
		done_len += pcm_len;
	}
}

static void record_stop_encode_amr(void){
#ifdef LUAT_USE_INTER_AMR
	luat_audio_inter_amr_coder_deinit(g_s_record.encoder_handler);
#else
	Encoder_Interface_exit(g_s_record.encoder_handler);
#endif
	g_s_record.encoder_handler = NULL;
}
#endif

static void record_stop(uint8_t *data, uint32_t len);
static void record_buffer_full(void)
{
	rtos_msg_t msg = {0};
	msg.handler = l_multimedia_raw_handler;
	msg.arg1 = LUAT_MULTIMEDIA_CB_RECORD_DATA;
	msg.arg2 = g_s_record.multimedia_id;
	msg.ptr = (void *)((uint32_t)g_s_record.record_buffer_index);
	luat_msgbus_put(&msg, 1);
	g_s_record.record_buffer_index = !g_s_record.record_buffer_index;
	g_s_record.record_buffer[g_s_record.record_buffer_index]->used = 0;
}
static void record_run(uint8_t *data, uint32_t len)
{

	if (g_s_record.fd){
#ifdef LUAT_SUPPORT_AMR
		if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
			record_encode_amr(data, len);
		}
		else
#endif
		{
			luat_fs_fwrite(data, len, 1, g_s_record.fd);
		}
	}else{
		memcpy(g_s_record.record_buffer[g_s_record.record_buffer_index]->addr + g_s_record.record_buffer[g_s_record.record_buffer_index]->used, data, len);
		g_s_record.record_buffer[g_s_record.record_buffer_index]->used += len;
		if (g_s_record.record_buffer[g_s_record.record_buffer_index]->used >= g_s_record.record_callback_level)
		{
			record_buffer_full();
		}
	}
	if (g_s_record.record_time)
	{
		g_s_record.record_time_tmp++;
		if (g_s_record.record_time_tmp >= (g_s_record.record_time * 10) )
		{
			record_stop(NULL, 0);
		}
	}
}

static int record_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{
	switch(event)
	{
	case LUAT_I2S_EVENT_RX_DONE:
		luat_audio_run_callback_in_task(record_run, rx_data, rx_len);
		break;
	default:
		break;
	}
	return 0;
}

static void record_no_i2s_cb(uint8_t id, uint8_t *rx_data, uint32_t rx_len, void *param)
{
	luat_audio_run_callback_in_task(record_run, rx_data, rx_len);
}

static void record_start(uint8_t *data, uint32_t len){



    //需要保存文件，看情况打开编码功能
    if (g_s_record.fd){
        if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
#ifdef LUAT_USE_INTER_AMR
            g_s_record.encoder_handler = luat_audio_inter_amr_coder_init(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB?0:1, g_s_record.quailty);
#else
            g_s_record.encoder_handler = Encoder_Interface_init(g_s_record.quailty);
#endif
			if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB){
				luat_fs_fwrite("#!AMR\n", 6, 1, g_s_record.fd);
			}else{
				luat_fs_fwrite("#!AMR-WB\n", 9, 1, g_s_record.fd);
			}
#endif
        }
    }
    luat_audio_conf_t *audio = luat_audio_get_config(g_s_record.multimedia_id);
    if (LUAT_AUDIO_BUS_I2S == audio->bus_type)
    {
    	luat_i2s_conf_t *i2s = luat_i2s_get_config(g_s_record.multimedia_id);
    	g_s_record.bak_cb_rx_len = i2s->cb_rx_len;
    	g_s_record.bak_is_full_duplex = i2s->is_full_duplex;
    	g_s_record.bak_sample_rate = i2s->sample_rate;
    	g_s_record.bak_luat_i2s_event_callback = i2s->luat_i2s_event_callback;


    	i2s->is_full_duplex = 1;
    	i2s->luat_i2s_event_callback = record_cb;
    	switch(g_s_record.type)
    	{
    	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB:
    	case LUAT_MULTIMEDIA_DATA_TYPE_PCM:
        	i2s->cb_rx_len = 320 * RECORD_ONCE_LEN;
            i2s->sample_rate = 8000;
            break;
    	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
        	i2s->cb_rx_len = 640 * RECORD_ONCE_LEN;
            i2s->sample_rate = 16000;
            break;
    	default:
    		if (g_s_record.type <= 32000)
    		{
    			i2s->cb_rx_len = g_s_record.type / 5;
    		}
    		else if (g_s_record.type < 80000)
    		{
    			i2s->cb_rx_len = g_s_record.type / 10;
    		}
    		else
    		{
    			i2s->cb_rx_len = g_s_record.type / 20;
    		}
            i2s->sample_rate = g_s_record.type;
    		break;
    	}
    	luat_audio_record_and_play(g_s_record.multimedia_id, i2s->sample_rate, NULL, 3200, 2);
    } else { //非I2S的录音device
    	uint32_t sample_rate = 8000;
    	if (g_s_record.type >= 8000)
    	{
    		sample_rate = g_s_record.type;
    	}
    	else
    	{
        	switch(g_s_record.type)
        	{
        	case LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB:
        		sample_rate = 16000;
        		break;
        	}
    	}
    	luat_audio_setup_record_callback(g_s_record.multimedia_id, record_no_i2s_cb, &g_s_record);
    	luat_audio_record_and_play(g_s_record.multimedia_id, sample_rate, NULL, 3200, 2);
    }

}


static void record_stop(uint8_t *data, uint32_t len){
	rtos_msg_t msg = {0};
	//关闭audio硬件功能
	luat_audio_record_stop(g_s_record.multimedia_id);
	luat_audio_pm_request(g_s_record.multimedia_id, LUAT_AUDIO_PM_STANDBY);
    luat_audio_conf_t *audio = luat_audio_get_config(g_s_record.multimedia_id);
    if (LUAT_AUDIO_BUS_I2S == audio->bus_type)
    {
    	//还原参数
    	luat_i2s_conf_t *i2s = luat_i2s_get_config(g_s_record.multimedia_id);
    	i2s->cb_rx_len = g_s_record.bak_cb_rx_len;
    	i2s->is_full_duplex = g_s_record.bak_is_full_duplex;
    	i2s->sample_rate = g_s_record.bak_sample_rate;
    	i2s->luat_i2s_event_callback = g_s_record.bak_luat_i2s_event_callback;
    }

	//录音存文件时，看情况关闭编码功能
	if (g_s_record.fd) {
		if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
			record_stop_encode_amr();
#endif
		}else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_PCM){
			// 不需要特殊处理
		}
		luat_fs_fclose(g_s_record.fd);
		g_s_record.fd = NULL;
	}
	//通知luat task清除zbuff数据，并回调用户
	msg.handler = l_multimedia_raw_handler;
	msg.arg1 = LUAT_MULTIMEDIA_CB_RECORD_DONE;
	msg.arg2 = g_s_record.multimedia_id;
	g_s_record.record_time_tmp = 0;
	g_s_record.is_run = 0;
	g_s_record.record_buffer_index = 0;
	luat_msgbus_put(&msg, 1);
}

/**
录音
@api audio.record(id, record_type, record_time, amr_quailty, path, record_callback_time, buff0, buff1,channelCount)
@int id             多媒体播放通道号
@int record_type    录音音频格式,支持 audio.AMR audio.PCM (部分平台支持audio.AMR_WB),或者直接输入采样率
@int record_time    录制时长 单位秒,可选，默认0即表示一直录制
@int amr_quailty    质量,audio.AMR下有效
@string path        录音文件路径,可选,不指定则不保存,可在audio.on回调函数中处理原始PCM数据
@int record_callback_time	不指定录音文件路径时，单次录音回调时长，单位是100ms。默认1，既100ms
@zbuff				录音原始PCM数据缓存0,不填写录音文件路径才会用到
@zbuff				录音原始PCM数据缓存1,不填写录音文件路径才会用到
@channelCount		声道数量,只针对非I2S设备有效,1单声道录音 2立体声录音 默认单声道.I2S设备在I2S相关API里配置
@return boolean     成功返回true,否则返回false
@usage
err,info = audio.record(id, type, record_time, quailty, path)
*/
static int l_audio_record(lua_State *L){
    size_t len;
    uint32_t record_buffer_len;
    g_s_record.multimedia_id = luaL_checkinteger(L, 1);
    g_s_record.type = luaL_optinteger(L, 2,LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB);
    g_s_record.record_time = luaL_optinteger(L, 3, 0);
    g_s_record.quailty = luaL_optinteger(L, 4, 0);
    if (g_s_record.fd || g_s_record.is_run) {
    	LLOGE("record is running");
    	goto ERROR_OUT;
    }
    if (lua_isstring(L, 5)) {
        const char *path = luaL_checklstring(L, 5, &len);
        luat_fs_remove(path);
        g_s_record.fd = luat_fs_fopen(path, "wb+");
        if(!g_s_record.fd){
            LLOGE("open file %s failed", path);
            goto ERROR_OUT;
        }
    } else {
    	if (!lua_isuserdata(L, 7) || !lua_isuserdata(L, 8))
    	{
    		goto ERROR_OUT;
    	}
    }

    record_buffer_len = luaL_optinteger(L, 6, 1);
	g_s_record.channelCnt = luaL_optinteger(L, 9, LUAT_RECORD_MONO);
    if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB||g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_SUPPORT_AMR
    if (g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB){
        record_buffer_len *= 320 * RECORD_ONCE_LEN;
    }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB){
#ifdef LUAT_USE_INTER_AMR
        record_buffer_len *= 640 * RECORD_ONCE_LEN;
#else
    LLOGE("not support 16k");
    return 0;
#endif
    }
    
#else
    LLOGE("not support AMR");
    return 0;
#endif
    }else if(g_s_record.type==LUAT_MULTIMEDIA_DATA_TYPE_PCM){
        record_buffer_len *= 320 * RECORD_ONCE_LEN;
    }else if (g_s_record.type >= 8000 ){
    	record_buffer_len *= (g_s_record.type/5);
    } else
    {
        LLOGE("not support type %d", g_s_record.type);
        goto ERROR_OUT;
    }
    if (!g_s_record.fd)
    {
    	g_s_record.record_callback_level = record_buffer_len;
    	g_s_record.record_buffer[0] = ((luat_zbuff_t *)luaL_checkudata(L, 7, LUAT_ZBUFF_TYPE));
    	g_s_record.record_buffer[1] = ((luat_zbuff_t *)luaL_checkudata(L, 8, LUAT_ZBUFF_TYPE));
    	g_s_record.record_buffer[0]->used = 0;
    	g_s_record.record_buffer[1]->used = 0;
    	if (g_s_record.record_buffer[0]->len < record_buffer_len)
    	{
    		__zbuff_resize(g_s_record.record_buffer[0], record_buffer_len);
    	}
    	if (g_s_record.record_buffer[1]->len < record_buffer_len)
    	{
    		__zbuff_resize(g_s_record.record_buffer[1], record_buffer_len);
    	}
    }

    g_s_record.is_run = 1;
    luat_audio_run_callback_in_task(record_start, NULL, 0);
    lua_pushboolean(L, 1);
    return 1;
ERROR_OUT:
    lua_pushboolean(L, 0);
    return 1;
}

/**
录音停止
@api audio.recordStop(id)
@int id         多媒体播放通道号
@return boolean 成功返回true,否则返回false
@usage
audio.recordStop(0)
*/
static int l_audio_record_stop(lua_State *L) {

    if (g_s_record.is_run) {
    	luat_audio_run_callback_in_task(record_stop, NULL, 0);
        lua_pushboolean(L, 1);
        return 1;
    } else {
        LLOGE("record is not running");
        return 0;
    }
}

#endif

/**
往一个多媒体通道写入音频数据
@api audio.write(id, data)
@string/zbuff 音频数据
@return boolean 成功返回true,否则返回false
@usage
audio.write(0, "xxxxxx")
*/
static int l_audio_write_raw(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    size_t len;
    const char *buf;
    if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        len = buff->used;
        buf = (const char *)(buff->addr);
    }
    else
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
    }
	lua_pushboolean(L, !luat_audio_write_raw(multimedia_id, (uint8_t*)	, len));
    return 1;
}

/**
停止指定的多媒体通道
@api audio.stop(id)
@int audio id,例如0
@return boolean 成功返回true,否则返回false
@usage
audio.stop(0)
*/
static int l_audio_stop_raw(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    lua_pushboolean(L, !luat_audio_stop_raw(multimedia_id));
    return 1;
}

/**
暂停/恢复指定的多媒体通道
@api audio.pause(id, pause)
@int audio id,例如0
@boolean onoff true 暂停，false 恢复
@return boolean 成功返回true,否则返回false
@usage
audio.pause(0, true) --暂停通道0
audio.pause(0, false) --恢复通道0
*/
static int l_audio_pause_raw(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    lua_pushboolean(L, !luat_audio_pause_raw(multimedia_id, lua_toboolean(L, 2)));
    return 1;
}

/**
注册audio播放事件回调
@api    audio.on(audio_id, func)
@int audio id, audio 0写0, audio 1写1
@function 回调方法，回调时传入参数为1、int 通道ID 2、int 消息值，有audio.MORE_DATA,audio.DONE,audio.RECORD_DATA,audio.RECORD_DONE,3、RECORD_DATA后面跟数据存在哪个zbuff内，0或者1
@return nil 无返回值
@usage
audio.on(0, function(audio_id, msg)
    log.info("msg", audio_id, msg)
end)
*/
static int l_audio_raw_on(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
	if (multimedia_cbs[multimedia_id].function_ref != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, multimedia_cbs[multimedia_id].function_ref);
		multimedia_cbs[multimedia_id].function_ref = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		multimedia_cbs[multimedia_id].function_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

    return 0;
}

/*
播放或者停止播放一个文件，播放完成后，会回调一个audio.DONE消息，可以用pause来暂停或者恢复，其他API不可用。考虑到读SD卡速度比较慢而拖累luavm进程的速度，所以尽量使用本API
@api audio.play(id, path, errStop)
@int 音频通道
@string/table 文件名，如果为空，则表示停止播放，如果是table，则表示连续播放多个文件，主要应用于云喇叭，目前只有Air780EXXX支持，并且会用到errStop参数
@boolean 是否在文件解码失败后停止解码，只有在连续播放多个文件时才有用，默认true，遇到解码错误自动停止
@return boolean 成功返回true,否则返回false
@usage
audio.play(0, "xxxxxx")		--开始播放某个文件
audio.play(0)				--停止播放某个文件
*/
static int l_audio_play(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    size_t len = 0;
    int result = 0;
    const char *buf;
    uint8_t is_error_stop = 1;
    if (lua_istable(L, 2))
    {
    	size_t len = lua_rawlen(L, 2); //返回数组的长度
    	if (!len)
    	{
        	luat_audio_play_stop(multimedia_id);
        	lua_pushboolean(L, 1);
        	return 1;
    	}
        uData_t *info = (uData_t *)luat_heap_malloc(len * sizeof(uData_t));
        for (size_t i = 0; i < len; i++)
        {
            lua_rawgeti(L, 2, 1 + i);
            info[i].value.asBuffer.buffer = (void*)lua_tolstring(L, -1, &info[i].value.asBuffer.length);
            info[i].Type = UDATA_TYPE_OPAQUE;
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
    	if (lua_isboolean(L, 3))
    	{
    		is_error_stop = lua_toboolean(L, 3);
    	}
        result = luat_audio_play_multi_files(multimedia_id, info, len, is_error_stop);
    	lua_pushboolean(L, !result);
    	luat_heap_free(info);
    }
    else if (LUA_TSTRING == (lua_type(L, (2))))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        result = luat_audio_play_file(multimedia_id, buf);
    	lua_pushboolean(L, !result);
    }
    else
    {
    	luat_audio_play_stop(multimedia_id);
    	lua_pushboolean(L, 1);
    }
    return 1;
}
#ifdef LUAT_USE_TTS
/*
TTS播放或者停止
@api audio.tts(id, data)
@int 音频通道
@string/zbuff 需要播放的内容
@return boolean 成功返回true,否则返回false
@tag LUAT_USE_TTS
@usage
audio.tts(0, "测试一下")		--开始播放
audio.tts(0)				--停止播放
-- Air780E的TTS功能详细说明
-- https://wiki.luatos.com/chips/air780e/tts.html
*/
static int l_audio_play_tts(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    size_t len = 0;
    int result = 0;
    const char *buf;
    if (LUA_TSTRING == (lua_type(L, (2))))
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
        result = luat_audio_play_tts_text(multimedia_id, (void*)buf, len);
    	lua_pushboolean(L, !result);
    }
    else if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        result = luat_audio_play_tts_text(multimedia_id, buff->addr, buff->used);
    	lua_pushboolean(L, !result);
    }
    else
    {
    	luat_audio_play_stop(multimedia_id);
    	lua_pushboolean(L, 1);
    }
    return 1;
}
#endif
/**
停止播放文件，和audio.play(id)是一样的作用
@api audio.playStop(id)
@int audio id,例如0
@return boolean 成功返回true,否则返回false
@usage
audio.playStop(0)
*/
static int l_audio_play_stop(lua_State *L) {
	uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    lua_pushboolean(L, !luat_audio_play_stop(multimedia_id));
    return 1;
}


/**
检查当前文件是否已经播放结束
@api audio.isEnd(id)
@int 音频通道
@return boolean 成功返回true,否则返回false
@usage
audio.isEnd(0)

*/
static int l_audio_play_wait_end(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    lua_pushboolean(L, luat_audio_is_finish(multimedia_id));
    return 1;
}

/*
获取最近一次播放结果，不是所有平台都支持的，目前只有Air780EXXX支持
@api audio.getError(id)
@int 音频通道
@return boolean 是否全部播放成功，true成功，false有文件播放失败
@return boolean 如果播放失败，是否是用户停止，true是，false不是
@return int 第几个文件失败了，从1开始
@usage
local result, user_stop, file_no = audio.getError(0)
*/
static int l_audio_play_get_last_error(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
	int result = luat_audio_play_get_last_error(multimedia_id);
	lua_pushboolean(L, 0 == result);
	lua_pushboolean(L, result < 0);
	lua_pushinteger(L, result > 0?result:0);
    return 3;
}

/*
配置一个音频通道的特性，比如实现自动控制PA开关。注意这个不是必须的，一般在调用play的时候才需要自动控制，其他情况比如你手动控制播放时，就可以自己控制PA开关
@api audio.config(id, paPin, onLevel, dacDelay, paDelay, dacPin, dacLevel, dacTimeDelay)
@int 音频通道
@int PA控制IO
@int PA打开时的电平
@int 在DAC启动前插入的冗余时间，单位100ms，一般用于外部DAC
@int 在DAC启动后，延迟多长时间打开PA，单位1ms
@int 外部dac电源控制IO，如果不填，则表示使用平台默认IO，比如Air780E使用DACEN脚，air105则不启用
@int 外部dac打开时，电源控制IO的电平，默认拉高
@int 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms，默认0ms
@usage
--下面的配置是Air780E云喇叭板的配置
audio.config(0, 25, 1, 6, 200)	--PA控制脚是GPIO25，高电平打开
*/
static int l_audio_config(lua_State *L) {
    uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	if (multimedia_id >= MAX_DEVICE_COUNT) {
		LLOGE("multimedia_id %d is out of range", multimedia_id);
		return 0;
	}
    int pa_pin = luaL_optinteger(L, 2, -1);
    int level = luaL_optinteger(L, 3, 1);
    int dac_pre_delay = luaL_optinteger(L, 4, 5);
    int dac_last_delay = luaL_optinteger(L, 5, 200);
    int dac_power_pin = luaL_optinteger(L, 6, -1);
    int dac_power_level = luaL_optinteger(L, 7, 1);
    int pa_dac_delay = luaL_optinteger(L, 8, 0);
    if (pa_dac_delay < 0)
        pa_dac_delay = 0;
    if (dac_pre_delay < 0)
        dac_pre_delay = 0;
    if (dac_last_delay < 0)
        dac_last_delay = 0;
    luat_audio_config_pa(multimedia_id, pa_pin, level, (uint32_t)dac_pre_delay, (uint32_t)dac_last_delay);
    luat_audio_config_dac(multimedia_id, dac_power_pin, dac_power_level, (uint32_t)pa_dac_delay);
    return 0;
}

/*
配置一个音频通道的音量调节，直接将原始数据放大或者缩小，不是所有平台都支持，建议尽量用硬件方法去缩放
@api audio.vol(id, value)
@int 音频通道
@int 音量，百分比，1%~1000%，默认100%，就是不调节
@return int 当前音量
@usage
local result = audio.vol(0, 90)	--通道0的音量调节到90%，result存放了调节后的音量水平，有可能仍然是100
*/
static int l_audio_vol(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int vol = luaL_optinteger(L, 2, 100);
    lua_pushinteger(L, luat_audio_vol(id, vol));
    return 1;
}

/*
配置一个音频通道的mic音量调节
@api audio.micVol(id, value)
@int 音频通道
@int mic音量，百分比，1%~100%，默认100%，就是不调节
@return int 当前mic音量
@usage
local result = audio.vol(0, 90)	--通道0的音量调节到90%，result存放了调节后的音量水平，有可能仍然是100
*/
static int l_audio_mic_vol(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int mic_vol = luaL_optinteger(L, 2, 100);
    lua_pushinteger(L, luat_audio_mic_vol(id, mic_vol));
    return 1;
}

/*
配置一个音频通道的硬件输出总线，只有对应soc软硬件平台支持才设置对应类型
@api audio.setBus(id, bus_type)
@int 音频通道,例如0
@int 总线类型, 例如 audio.BUS_SOFT_DAC, audio.BUS_I2S
@table codec配置参数, 当总线类型为audio.BUS_I2S时生效,table中包括以下字段: <br>chip codec型号,当前支持"es8311"<br>i2cid codec的硬件i2c id<br>i2sid codec的硬件i2s id<br>voltage i2cid codec的电压,可选 codec.VDDA_3V3 codec.VDDA_1V8
@return nil 无返回值
@usage
audio.setBus(0, audio.BUS_SOFT_DAC)	--通道0的硬件输出通道设置为软件DAC
audio.setBus(0, audio.BUS_I2S,{chip="es8311",i2cid=0,i2sid=0,voltage=codec.VDDA_3V3})	--通道0的硬件输出通道设置为I2S
*/
static int l_audio_set_output_bus(lua_State *L) {
    size_t len;
    int id = luaL_checkinteger(L, 1);
    luat_audio_conf_t* audio_conf = luat_audio_get_config(id);
    int tp = luaL_checkinteger(L, 2);
    int ret = luat_audio_set_bus_type(id,tp);
    if (audio_conf!=NULL && lua_istable(L,3) && tp==LUAT_AUDIO_BUS_I2S){
        audio_conf->codec_conf.multimedia_id = id;
        audio_conf->bus_type = LUAT_AUDIO_BUS_I2S;
        audio_conf->codec_conf.codec_opts = &codec_opts_common;
		lua_pushstring(L, "chip");
		if (LUA_TSTRING == lua_gettable(L, 3)) {
            const char *chip = luaL_checklstring(L, -1,&len);
            if(strcmp(chip,"es8311") == 0){
                audio_conf->codec_conf.codec_opts = &codec_opts_es8311;
            }
		}
		lua_pop(L, 1);
		lua_pushstring(L, "i2cid");
		if (LUA_TNUMBER == lua_gettable(L, 3)) {
			audio_conf->codec_conf.i2c_id = luaL_checknumber(L, -1);
		}
		lua_pop(L, 1);
		lua_pushstring(L, "i2sid");
		if (LUA_TNUMBER == lua_gettable(L, 3)) {
			audio_conf->codec_conf.i2s_id = luaL_checknumber(L, -1);
		}
		lua_pop(L, 1);
		lua_pushstring(L, "voltage");
		if (LUA_TNUMBER == lua_gettable(L, 3)) {
			audio_conf->voltage = luaL_checknumber(L, -1);
		}
		lua_pop(L, 1);
    }
    ret |= luat_audio_init(id, 0, 0);
    lua_pushboolean(L, !ret);
    return 1;
}

LUAT_WEAK void luat_audio_set_debug(uint8_t on_off)
{
	(void)on_off;
}
/*
配置调试信息输出
@api audio.debug(on_off)
@boolean true开 false关
@return
@usage
audio.debug(true)	--开启调试信息输出
audio.debug(false)	--关闭调试信息输出
*/
static int l_audio_set_debug(lua_State *L) {
	luat_audio_set_debug(lua_toboolean(L, 1));
    return 0;
}

/*
audio 休眠控制(一般会自动调用不需要手动执行)
@api audio.pm(id,pm_mode)
@int 音频通道
@int 休眠模式 
@return boolean true成功
@usage
audio.pm(multimedia_id,audio.RESUME)
*/
static int l_audio_pm_request(lua_State *L) {
	uint8_t multimedia_id = (uint8_t)luaL_checkinteger(L, 1);
	luat_audio_pm_mode_t mode = (luat_audio_pm_mode_t)luaL_checkinteger(L, 2);
	int ret = luat_audio_pm_request(multimedia_id, mode);
    lua_pushboolean(L, !ret);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_audio[] =
{
    { "start" ,        ROREG_FUNC(l_audio_start_raw)},
    { "write" ,        ROREG_FUNC(l_audio_write_raw)},
    { "pause",         ROREG_FUNC(l_audio_pause_raw)},
	{ "stop",		   ROREG_FUNC(l_audio_stop_raw)},
    { "on",            ROREG_FUNC(l_audio_raw_on)},
	{ "play",		   ROREG_FUNC(l_audio_play)},
#ifdef LUAT_USE_TTS
	{ "tts",		   ROREG_FUNC(l_audio_play_tts)},
#endif
	{ "playStop",	   ROREG_FUNC(l_audio_play_stop)},
	{ "isEnd",		   ROREG_FUNC(l_audio_play_wait_end)},
	{ "config",			ROREG_FUNC(l_audio_config)},
	{ "vol",			ROREG_FUNC(l_audio_vol)},
    { "micVol",			ROREG_FUNC(l_audio_mic_vol)},
	{ "getError",		ROREG_FUNC(l_audio_play_get_last_error)},
	{ "setBus",			ROREG_FUNC(l_audio_set_output_bus)},
	{ "debug",			ROREG_FUNC(l_audio_set_debug)},
    { "pm",			    ROREG_FUNC(l_audio_pm_request)},
#ifdef LUAT_USE_RECORD
    { "record",			ROREG_FUNC(l_audio_record)},
    { "recordStop",		ROREG_FUNC(l_audio_record_stop)},
    
#endif
	//@const RESUME number PM模式 工作模式
    { "RESUME",         ROREG_INT(LUAT_AUDIO_PM_RESUME)},
    //@const STANDBY number PM模式 待机模式，PA断电，codec待机状态，系统不能进低功耗状态，如果PA不可控，codec进入静音模式
    { "STANDBY",        ROREG_INT(LUAT_AUDIO_PM_STANDBY)},
    //@const SHUTDOWN number PM模式 关机模式，PA断电，可配置的codec关机状态，不可配置的codec断电，系统能进低功耗状态
    { "SHUTDOWN",       ROREG_INT(LUAT_AUDIO_PM_SHUTDOWN)},
	//@const POWEROFF number PM模式 断电模式，PA断电，codec断电，系统能进低功耗状态
    { "POWEROFF",         ROREG_INT(LUAT_AUDIO_PM_POWER_OFF)},
	//@const PCM number PCM格式，即原始ADC数据
    { "PCM",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_PCM)},
    //@const MP3 number MP3格式
    { "MP3",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_MP3)},
    //@const WAV number WAV格式
    { "WAV",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_WAV)},
    //@const AMR number AMR_NB格式
    { "AMR",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)},
    //@const AMR_NB number AMR_NB格式
    { "AMR_NB",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB)},
    //@const AMR_WB number AMR_WB格式
    { "AMR_WB",           ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB)},
	//@const ULAW number G711 ulaw格式
	{ "ULAW",             ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_ULAW)},
    //@const ALAW number G711 alaw格式
	{ "ALAW",             ROREG_INT(LUAT_MULTIMEDIA_DATA_TYPE_ALAW)},
	//@const MORE_DATA number audio.on回调函数传入参数的值，表示底层播放完一段数据，可以传入更多数据
	{ "MORE_DATA",     ROREG_INT(LUAT_MULTIMEDIA_CB_AUDIO_NEED_DATA)},
	//@const DONE number audio.on回调函数传入参数的值，表示底层播放完全部数据了
	{ "DONE",          ROREG_INT(LUAT_MULTIMEDIA_CB_AUDIO_DONE)},
	//@const RECORD_DATA number audio.on回调函数传入参数的值，表示录音数据
	{ "RECORD_DATA",     ROREG_INT(LUAT_MULTIMEDIA_CB_RECORD_DATA)},
	//@const RECORD_DONE number audio.on回调函数传入参数的值，表示录音完成
	{ "RECORD_DONE",          ROREG_INT(LUAT_MULTIMEDIA_CB_RECORD_DONE)},
	//@const BUS_DAC number 硬件输出总线，DAC类型
	{ "BUS_DAC", 		ROREG_INT(LUAT_AUDIO_BUS_DAC)},
	//@const BUS_I2S number 硬件输出总线，I2S类型
	{ "BUS_I2S", 		ROREG_INT(LUAT_AUDIO_BUS_I2S)},
	//@const BUS_SOFT_DAC number 硬件输出总线，软件模式DAC类型
	{ "BUS_SOFT_DAC", 		ROREG_INT(LUAT_AUDIO_BUS_SOFT_DAC)},
    //@const VOLTAGE_1800 number 可配置的codec工作电压，1.8V
	{ "VOLTAGE_1800", 		ROREG_INT(LUAT_AUDIO_VOLTAGE_1800)},
    //@const VOLTAGE_3300 number 可配置的codec工作电压，3.3V
	{ "VOLTAGE_3300", 		ROREG_INT(LUAT_AUDIO_VOLTAGE_3300)},
    //@const RECORD_MONO number 录音使用单声道
	{ "RECORD_MONO", 		ROREG_INT(LUAT_RECORD_MONO)},
    //@const RECORD_STEREO number 录音使用立体声
	{ "RECORD_STEREO", 		ROREG_INT(LUAT_RECORD_STEREO)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib2(L, reg_audio);
    return 1;
}
