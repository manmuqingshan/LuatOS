
/*
@module  audio
@summary 多媒体-音频
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_AUDIO_V2
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "audio_v2"
#include "luat_log.h"
#ifdef LUAT_USE_AUDIO_V2
#include "luat_audio_core.h"

#include "luat_mem.h"


/*
配置调试信息输出
@api audio_v2.debug(on_off)
@boolean true开 false关
@return
@usage
audio_v2.debug(true)	--开启调试信息输出
audio_v2.debug(false)	--关闭调试信息输出
*/
static int l_audio_set_debug(lua_State *L) {
	luat_audio_debug_switch(lua_toboolean(L, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_audio_v2[] =
{
	{ "debug",			ROREG_FUNC(l_audio_set_debug)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_audio_v2( lua_State *L ) {
    luat_newlib2(L, reg_audio_v2);
    return 1;
}
#endif