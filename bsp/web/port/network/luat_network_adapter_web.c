#include "luat_base.h"
#include "luat_log.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "web.net"
#include "luat_log.h"

#include <string.h>

static CBFuncEx_t g_cb = NULL;
static void *g_cb_param = NULL;

static uint8_t web_check_ready(void *user_data) {
    (void)user_data;
    return 0;
}

static int web_return_unavailable(void) {
    LLOGW("network access is not wired to the browser backend yet");
    return -1;
}

static int web_create_socket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data) {
    (void)is_tcp;
    (void)tag;
    (void)param;
    (void)is_ipv6;
    (void)user_data;
    return web_return_unavailable();
}

static int web_socket_connect(int socket_id, uint64_t tag, uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)local_port;
    (void)remote_ip;
    (void)remote_port;
    (void)user_data;
    return web_return_unavailable();
}

static int web_socket_listen(int socket_id, uint64_t tag, uint16_t local_port, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)local_port;
    (void)user_data;
    return web_return_unavailable();
}

static int web_socket_accept(int socket_id, uint64_t tag, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)remote_ip;
    (void)remote_port;
    (void)user_data;
    return web_return_unavailable();
}

static int web_socket_disconnect(int socket_id, uint64_t tag, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)user_data;
    return 0;
}

static int web_socket_close(int socket_id, uint64_t tag, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)user_data;
    return 0;
}

static int web_socket_force_close(int socket_id, void *user_data) {
    (void)socket_id;
    (void)user_data;
    return 0;
}

static int web_socket_receive(int socket_id, uint64_t tag, uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)buf;
    (void)len;
    (void)flags;
    (void)remote_ip;
    (void)remote_port;
    (void)user_data;
    return 0;
}

static int web_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)buf;
    (void)flags;
    (void)remote_ip;
    (void)remote_port;
    (void)user_data;
    return (int)len;
}

static int web_socket_check(int socket_id, uint64_t tag, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)user_data;
    return -1;
}

static void web_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data) {
    (void)vaild_socket_list;
    (void)num;
    (void)user_data;
}

static int web_getsockopt(int socket_id, uint64_t tag, int level, int optname, void *optval, uint32_t *optlen, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)level;
    (void)optname;
    (void)optval;
    (void)optlen;
    (void)user_data;
    return -1;
}

static int web_setsockopt(int socket_id, uint64_t tag, int level, int optname, const void *optval, uint32_t optlen, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)level;
    (void)optname;
    (void)optval;
    (void)optlen;
    (void)user_data;
    return -1;
}

static int web_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data) {
    (void)socket_id;
    (void)tag;
    (void)cmd;
    (void)value;
    (void)user_data;
    return -1;
}

static int web_dns(const char *domain_name, uint32_t len, void *param, void *user_data) {
    (void)domain_name;
    (void)len;
    (void)param;
    (void)user_data;
    return -1;
}

static int web_dns_ipv6(const char *domain_name, uint32_t len, void *param, void *user_data) {
    (void)domain_name;
    (void)len;
    (void)param;
    (void)user_data;
    return -1;
}

static int web_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data) {
    (void)server_index;
    (void)ip;
    (void)user_data;
    return 0;
}

static int web_set_mac(uint8_t *mac, void *user_data) {
    (void)mac;
    (void)user_data;
    return 0;
}

static int web_set_static_ip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data) {
    (void)ip;
    (void)submask;
    (void)gateway;
    (void)ipv6;
    (void)user_data;
    return 0;
}

static int web_get_full_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data) {
    if (ip) memset(ip, 0, sizeof(*ip));
    if (submask) memset(submask, 0, sizeof(*submask));
    if (gateway) memset(gateway, 0, sizeof(*gateway));
    if (ipv6) memset(ipv6, 0, sizeof(*ipv6));
    (void)user_data;
    return 0;
}

static int web_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data) {
    if (ip) memset(ip, 0, sizeof(*ip));
    if (submask) memset(submask, 0, sizeof(*submask));
    if (gateway) memset(gateway, 0, sizeof(*gateway));
    (void)user_data;
    return 0;
}

static void web_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data) {
    (void)user_data;
    g_cb = cb_fun;
    g_cb_param = param;
}

static int web_check_ack(uint8_t adapter_index, int socket_id) {
    (void)adapter_index;
    (void)socket_id;
    return 0;
}

static network_adapter_info g_web_adapter = {
    .check_ready = web_check_ready,
    .create_soceket = web_create_socket,
    .socket_connect = web_socket_connect,
    .socket_listen = web_socket_listen,
    .socket_accept = web_socket_accept,
    .socket_disconnect = web_socket_disconnect,
    .socket_close = web_socket_close,
    .socket_force_close = web_socket_force_close,
    .socket_receive = web_socket_receive,
    .socket_send = web_socket_send,
    .socket_check = web_socket_check,
    .socket_clean = web_socket_clean,
    .getsockopt = web_getsockopt,
    .setsockopt = web_setsockopt,
    .user_cmd = web_user_cmd,
    .dns = web_dns,
    .dns_ipv6 = web_dns_ipv6,
    .set_dns_server = web_set_dns_server,
    .set_mac = web_set_mac,
    .set_static_ip = web_set_static_ip,
    .get_full_ip_info = web_get_full_ip_info,
    .get_local_ip_info = web_get_local_ip_info,
    .socket_set_callback = web_socket_set_callback,
    .check_ack = web_check_ack,
    .name = "web",
    .max_socket_num = 1,
    .no_accept = 1,
    .is_posix = 0,
};

void luat_network_init(void) {
    network_register_adapter(NW_ADAPTER_INDEX_CUSTOM, &g_web_adapter, NULL);
    network_register_set_default(NW_ADAPTER_INDEX_CUSTOM);
    LLOGI("browser network adapter registered");
    if (g_cb) {
        (void)g_cb_param;
    }
}
