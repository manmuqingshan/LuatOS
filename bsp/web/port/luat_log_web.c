#define LUAT_LOG_TAG "log.web"
#include "luat_log.h"

#include "luat_base.h"
#include <stdio.h>

void luat_log_init_win32(void) {
}

void luat_log_deinit_win32(void) {
}

void luat_log_set_uart_port(int port) {
    (void)port;
}

void luat_print(const char *str) {
    if (str) {
        fputs(str, stdout);
        fflush(stdout);
    }
}

void luat_nprint(char *s, size_t l) {
    if (s && l) {
        fwrite(s, 1, l, stdout);
        fflush(stdout);
    }
}

void luat_log_write(char *s, size_t l) {
    luat_nprint(s, l);
}

void luat_log_set_level(int level) {
    (void)level;
}
