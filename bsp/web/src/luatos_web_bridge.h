#ifndef LUATOS_WEB_BRIDGE_H
#define LUATOS_WEB_BRIDGE_H

#include "luat_base.h"

void luatos_web_bridge_init(void);
void luatos_web_bridge_set_status(const char *status);
void luatos_web_bridge_log(const char *tag, const char *message);

#endif
