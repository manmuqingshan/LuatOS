#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_pc_dtls_utest.h"

#include <string.h>

struct luat_pc_dtls_utest_server {
    volatile int ready;
    volatile int stop_requested;
    volatile int done;
    volatile int result;
    uint16_t port;
    char error_stage[32];
};

static void dtls_utest_set_error(luat_pc_dtls_utest_server_t *server, const char *stage) {
    size_t n = strlen(stage);
    if (n >= sizeof(server->error_stage)) {
        n = sizeof(server->error_stage) - 1;
    }
    memcpy(server->error_stage, stage, n);
    server->error_stage[n] = 0;
}

int luat_pc_dtls_utest_server_start(luat_pc_dtls_utest_server_t **out_server,
                                    const char *psk_id,
                                    const uint8_t *psk,
                                    size_t psk_len) {
    (void)psk_id;
    (void)psk;
    (void)psk_len;
    *out_server = luat_heap_malloc(sizeof(luat_pc_dtls_utest_server_t));
    if (!*out_server) {
        return -1;
    }
    memset(*out_server, 0, sizeof(luat_pc_dtls_utest_server_t));
    dtls_utest_set_error(*out_server, "helper_start_failed");
    return 0;
}

int luat_pc_dtls_utest_server_wait_ready(luat_pc_dtls_utest_server_t *server,
                                         uint32_t timeout_ms,
                                         uint16_t *out_port) {
    (void)server;
    (void)timeout_ms;
    (void)out_port;
    return -1;
}

const char *luat_pc_dtls_utest_server_error(luat_pc_dtls_utest_server_t *server) {
    return server ? server->error_stage : "helper_start_failed";
}

int luat_pc_dtls_utest_server_stop(luat_pc_dtls_utest_server_t *server,
                                   uint32_t timeout_ms) {
    (void)timeout_ms;
    if (server) {
        luat_heap_free(server);
    }
    return 0;
}
