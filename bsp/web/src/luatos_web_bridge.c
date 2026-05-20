#define LUAT_LOG_TAG "web.bridge"
#include "luat_log.h"

#include "luat_base.h"
#include "luatos_web_bridge.h"

void luatos_web_bridge_init(void) {
    LLOGI("web bridge ready");
}

void luatos_web_bridge_set_status(const char *status) {
    if (status == NULL) {
        return;
    }
    LLOGI("status: %s", status);
}

void luatos_web_bridge_log(const char *tag, const char *message) {
    if (tag == NULL) {
        tag = "web";
    }
    if (message == NULL) {
        message = "";
    }
    LLOGI("%s: %s", tag, message);
}
