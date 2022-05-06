
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "platform_def.h"
#include "bsp_common.h"
#include "ctype.h"

extern void DBG_Printf(const char* format, ...);
extern void DBG_HexPrintf(void *Data, unsigned int len);
//#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
//#define DBG_ERR(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

#define __NW_DEBUG_ENABLE__
#ifdef __NW_DEBUG_ENABLE__
#define DBG(x,y...)	do {if (ctrl->is_debug) {DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y);}} while(0)
#define DBG_ERR(x,y...) do {if (ctrl->is_debug) {DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y);}} while(0)
#else
#define DBG(x,y...)
#define DBG_ERR(x,y...)
#endif
#define NW_LOCK		OS_SuspendTask(NULL)
#define NW_UNLOCK	OS_ResumeTask(NULL)

#define SOL_SOCKET  0xfff    /* options for socket level */
#define SO_REUSEADDR   0x0004 /* Allow local address reuse */
#define SO_KEEPALIVE   0x0008 /* keep connections alive */

#define IPPROTO_ICMP    1
#define IPPROTO_TCP     6
#define TCP_NODELAY    0x01    /* don't delay send to coalesce packets */
#define TCP_KEEPALIVE  0x02    /* send KEEPALIVE probes when idle for pcb->keep_idle milliseconds */
#define TCP_KEEPIDLE   0x03    /* set pcb->keep_idle  - Same as TCP_KEEPALIVE, but use seconds for get/setsockopt */
#define TCP_KEEPINTVL  0x04    /* set pcb->keep_intvl - Use seconds for get/setsockopt */
#define TCP_KEEPCNT    0x05    /* set pcb->keep_cnt   - Use number of probes sent for get/setsockopt */

typedef struct
{
	int last_adapter_index;
	llist_head dns_cache_head;
	uint8_t is_init;
}network_info_t;

typedef struct
{

	network_adapter_info *opt;
	void *user_data;
	uint8_t *ctrl_busy;
	network_ctrl_t *ctrl_table;
	uint16_t port;
}network_adapter_t;

static network_adapter_t prv_adapter_table[NW_ADAPTER_QTY];
static network_info_t prv_network = {
		.last_adapter_index = -1,
		.is_init = 0,
};

static uint8_t network_check_ip_same(luat_ip_addr_t *ip1, luat_ip_addr_t *ip2)
{
	if (ip1->is_ipv6 != ip2->is_ipv6)
	{
		return 0;
	}
	if (ip1->is_ipv6)
	{
		return !memcmp(ip1->ipv6_u8_addr, ip2->ipv6_u8_addr, 16);
	}
	else
	{
		return (ip1->ipv4 == ip2->ipv4);
	}
}

static int network_base_tx(network_ctrl_t *ctrl, const uint8_t *data, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	int result = -1;
	if (ctrl->is_tcp)
	{
		result = network_socket_send(ctrl, data, len, flags, NULL, 0);
	}
	else
	{
		if (remote_ip)
		{
			result = network_socket_send(ctrl, data, len, flags, remote_ip, remote_port);
		}
		else
		{
			result = network_socket_send(ctrl, data, len, flags, ctrl->online_ip, ctrl->remote_port);
		}
	}
	if (result >= 0)
	{
		ctrl->tx_size += len;
	}
	else
	{
		ctrl->need_close = 1;
	}
	return result;
}

static int32_t tls_shorttimeout(void *data, void *param)
{
	network_ctrl_t *ctrl = (network_ctrl_t *)param;
	if (!ctrl->tls_mode)
	{
		platform_stop_timer(ctrl->tls_long_timer);
		return 0;
	}
	if (0 == ctrl->tls_timer_state)
	{
		ctrl->tls_timer_state = 1;
	}
	return 0;
}

static int32_t tls_longtimeout(void *data, void *param)
{
	network_ctrl_t *ctrl = (network_ctrl_t *)param;
	platform_stop_timer(ctrl->tls_short_timer);
	if (!ctrl->tls_mode)
	{
		return 0;
	}
	ctrl->tls_timer_state = 2;
}

static void tls_settimer( void *data, uint32_t int_ms, uint32_t fin_ms )
{
	network_ctrl_t *ctrl = (network_ctrl_t *)data;
	if (!ctrl->tls_mode)
	{
		return;
	}
	if (!fin_ms)
	{
		platform_stop_timer(ctrl->tls_short_timer);
		platform_stop_timer(ctrl->tls_long_timer);
		ctrl->tls_timer_state = -1;
		return ;
	}
	platform_start_timer(ctrl->tls_short_timer, int_ms, 0);
	platform_start_timer(ctrl->tls_long_timer, fin_ms, 0);
	ctrl->tls_timer_state = 0;
}

static int tls_gettimer( void *data )
{
	network_ctrl_t *ctrl = (network_ctrl_t *)data;
	if (!ctrl->tls_mode)
	{
		return -ERROR_PARAM_INVALID;
	}
	return ctrl->tls_timer_state;
}

static void tls_dbg(void *data, int level,
        const char *file, int line,
        const char *str)
{
	DBG_Printf("%s %d:%s", file, line, str);
}

static int tls_send(void *ctx, const unsigned char *buf, size_t len )
{
	network_ctrl_t *ctrl = (network_ctrl_t *)ctx;
	if (!ctrl->tls_mode)
	{
		return -ERROR_PERMISSION_DENIED;
	}
	if (network_base_tx(ctrl, buf, len, 0, NULL, 0) != len)
	{
		return -0x004E;
	}
	else
	{
		return len;
	}
}

static int tls_recv(void *ctx, unsigned char *buf, size_t len )
{
#ifdef LUAT_USE_TLS
	network_ctrl_t *ctrl = (network_ctrl_t *)ctx;
	luat_ip_addr_t remote_ip;
	uint16_t remote_port;
	int result = -1;
	if (!ctrl->tls_mode)
	{
		return -1;
	}
TLS_RECV:

	result = network_socket_receive(ctrl, buf, len, 0, &remote_ip, &remote_port);
	if (result < 0)
	{
		return -0x004C;
	}
	if (result > 0)
	{
		if (!ctrl->is_tcp)
		{
			if ((remote_port == ctrl->remote_port) && network_check_ip_same(&remote_ip, ctrl->online_ip))
			{
				goto TLS_RECV;
			}
		}
		return result;
	}
	return MBEDTLS_ERR_SSL_WANT_READ;
#else
	return -1;
#endif
}

static int network_get_host_by_name(network_ctrl_t *ctrl)
{
	ctrl->remote_ip.is_ipv6 = 0xff;
	if (network_string_is_ipv4(ctrl->domain_name, ctrl->domain_name_len))
	{
		ctrl->remote_ip.is_ipv6 = 0;
		ctrl->remote_ip.ipv4 = network_string_to_ipv4(ctrl->domain_name, ctrl->domain_name_len);
	}
	else
	{
		char *name = zalloc(ctrl->domain_name_len + 1);
		memcpy(name, ctrl->domain_name, ctrl->domain_name_len);
		network_string_to_ipv6(name, &ctrl->remote_ip);
		free(name);
	}
	if (ctrl->remote_ip.is_ipv6 != 0xff)
	{
		return 0;
	}
	else
	{
		return -1;
	}
}

static void network_update_dns_cache(network_ctrl_t *ctrl)
{

}

static void network_get_dns_cache(network_ctrl_t *ctrl)
{

}

static int network_base_connect(network_ctrl_t *ctrl, luat_ip_addr_t *remote_ip)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		network_force_close_socket(ctrl);
	}
	if (network_create_soceket(ctrl, remote_ip->is_ipv6) < 0)
	{
		network_clean_invaild_socket(ctrl->adapter_index);
		if (network_create_soceket(ctrl, remote_ip->is_ipv6) < 0)
		{
			return -1;
		}
	}
	if (adapter->opt->is_posix)
	{
		network_setsockopt(ctrl, SOL_SOCKET, SO_KEEPALIVE, (void *)&ctrl->tcp_keep_alive, sizeof(ctrl->tcp_keep_alive));
		if (ctrl->tcp_keep_alive)
		{
			network_setsockopt(ctrl, IPPROTO_TCP, TCP_KEEPIDLE, (void*)&ctrl->tcp_keep_idle, sizeof(ctrl->tcp_keep_idle));
			network_setsockopt(ctrl, IPPROTO_TCP, TCP_KEEPINTVL, (void *)&ctrl->tcp_keep_interval, sizeof(ctrl->tcp_keep_interval));
			network_setsockopt(ctrl, IPPROTO_TCP, TCP_KEEPCNT, (void *)&ctrl->tcp_keep_cnt, sizeof(ctrl->tcp_keep_cnt));
		}
	}
	else
	{
		network_user_cmd(ctrl, NW_CMD_AUTO_HEART_TIME, ctrl->tcp_keep_idle);
	}

	return network_socket_connect(ctrl, remote_ip);
}

static int network_prepare_connect(network_ctrl_t *ctrl)
{
	if (ctrl->remote_ip.is_ipv6 != 0xff)
	{
		;
	}
	else if (ctrl->domain_name)
	{
		if (network_get_host_by_name(ctrl))
		{
			if (network_dns(ctrl))
			{
				network_socket_force_close(ctrl);
				return -1;
			}
			ctrl->state = NW_STATE_WAIT_DNS;
			return 0;
		}
	}
	else
	{

		return -1;
	}

	if (network_base_connect(ctrl, &ctrl->remote_ip))
	{
		network_socket_force_close(ctrl);
		return -1;
	}
	ctrl->state = NW_STATE_CONNECTING;
	return 0;
}

static int network_state_link_off(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if (EV_NW_STATE == event->ID)
	{
		if (event->Param2)
		{
			ctrl->state = NW_STATE_OFF_LINE;
			if (NW_WAIT_LINK_UP == ctrl->wait_target_state)
			{
				return 0;
			}
			else if (NW_WAIT_ON_LINE == ctrl->wait_target_state)
			{
				if (network_prepare_connect(ctrl))
				{
					return -1;
				}
				return 1;
			}
		}
	}
	return 1;
}

static int network_state_off_line(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	return 1;
}

static int network_state_wait_dns(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if ((ctrl->need_close) || ctrl->wait_target_state != NW_WAIT_ON_LINE) return -1;
	switch(event->ID)
	{
	case EV_NW_RESET:
	case EV_NW_SOCKET_ERROR:
		return -1;
	case EV_NW_STATE:
		if (!event->Param2)
		{
			return -1;
		}
		break;
	case EV_NW_DNS_RESULT:
		if (event->Param1)
		{
			//更新dns cache
			ctrl->dns_ip = event->Param2;
			ctrl->dns_ip_nums = event->Param1;
			network_update_dns_cache(ctrl);
		}
		else
		{
			ctrl->dns_ip_nums = 0;
			network_get_dns_cache(ctrl);
			if (!ctrl->dns_ip_nums)
			{
				return -1;
			}

		}
		ctrl->dns_ip_cnt = 0;
		if (network_base_connect(ctrl, &ctrl->dns_ip[ctrl->dns_ip_cnt].ip))
		{
			network_socket_force_close(ctrl);
			return -1;
		}
		else
		{
			ctrl->state = NW_STATE_CONNECTING;
			return 1;
		}
	default:
		return 1;
	}
}

static int network_state_connecting(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if ((ctrl->need_close) || (ctrl->wait_target_state != NW_WAIT_ON_LINE)) return -1;
	switch(event->ID)
	{
	case EV_NW_RESET:
		return -1;
	case EV_NW_SOCKET_ERROR:
	case EV_NW_SOCKET_REMOTE_CLOSE:
	case EV_NW_SOCKET_CLOSE_OK:
		if (ctrl->remote_ip.is_ipv6 != 0xff)
		{
			return -1;
		}
		DBG("dns ip %d no connect!", ctrl->dns_ip_cnt);
		ctrl->dns_ip_cnt++;
		if (ctrl->dns_ip_cnt >= ctrl->dns_ip_nums)
		{
			return -1;
		}
		if (network_base_connect(ctrl, &ctrl->dns_ip[ctrl->dns_ip_cnt].ip))
		{
			network_socket_force_close(ctrl);
			return -1;
		}
		else
		{
			ctrl->state = NW_STATE_CONNECTING;
			return 1;
		}
		break;
	case EV_NW_STATE:
		if (!event->Param2)
		{
			return -1;
		}
		break;
	case EV_NW_SOCKET_LISTEN:
		if (ctrl->is_server_mode)
		{
			ctrl->state = NW_STATE_LISTEN;
			return 0;
		}
		break;
	case EV_NW_SOCKET_CONNECT_OK:
#ifdef LUAT_USE_TLS
		if (ctrl->tls_mode)
		{
			mbedtls_ssl_free(ctrl->ssl);
			memset(ctrl->ssl, 0, sizeof(mbedtls_ssl_context));
			mbedtls_ssl_setup(ctrl->ssl, ctrl->config);
			ctrl->ssl->f_set_timer = tls_settimer;
			ctrl->ssl->f_get_timer = tls_gettimer;
			ctrl->ssl->p_timer = ctrl;
			ctrl->ssl->p_bio = ctrl;
			ctrl->ssl->f_send = tls_send;
			ctrl->ssl->f_recv = tls_recv;

			ctrl->state = NW_STATE_SHAKEHAND;
	    	do
	    	{
	    		int result = mbedtls_ssl_handshake_step( ctrl->ssl );
	    		switch(result)
	    		{
	    		case MBEDTLS_ERR_SSL_WANT_READ:
	    			return 1;
	    		case 0:
	    			break;
	    		default:
	    			DBG_ERR("0x%x, %d", -result, ctrl->ssl->state);
	    			return -1;
	    		}
	    	}while(ctrl->ssl->state != MBEDTLS_SSL_HANDSHAKE_OVER);
	    	return 0;
		}
		else
#endif
		{
			ctrl->state = NW_STATE_ONLINE;
			return 0;
		}

	default:
		return 1;
	}
}

static int network_state_shakehand(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if ((ctrl->need_close) || ((ctrl->wait_target_state != NW_WAIT_ON_LINE) && (ctrl->wait_target_state != NW_WAIT_TX_OK))) return -1;
	switch(event->ID)
	{
	case EV_NW_RESET:
	case EV_NW_SOCKET_ERROR:
	case EV_NW_SOCKET_REMOTE_CLOSE:
	case EV_NW_SOCKET_CLOSE_OK:
		ctrl->need_close = 1;
		return -1;
	case EV_NW_STATE:
		if (!event->Param2)
		{
			ctrl->need_close = 1;
			return -1;
		}
		break;
	case EV_NW_SOCKET_TX_OK:
		ctrl->ack_size += event->Param2;
		if (ctrl->is_debug)
		{
			DBG("%llu,%llu",ctrl->tx_size, ctrl->ack_size);
		}
		break;
#ifdef LUAT_USE_TLS
	case EV_NW_SOCKET_RX_NEW:

    	do
    	{
    		int result = mbedtls_ssl_handshake_step( ctrl->ssl );
    		switch(result)
    		{
    		case MBEDTLS_ERR_SSL_WANT_READ:
    			return 1;
    		case 0:
    			break;
    		default:
    			DBG_ERR("0x%x, %d", -result, ctrl->ssl->state);
    			ctrl->need_close = 1;
    			return -1;
    		}
    	}while(ctrl->ssl->state != MBEDTLS_SSL_HANDSHAKE_OVER);
    	ctrl->state = NW_STATE_ONLINE;
    	if (NW_WAIT_TX_OK == ctrl->wait_target_state)
    	{
    		if (!ctrl->cache_data)
    		{
    			ctrl->need_close = 1;
    			return -1;
    		}
    		int result = mbedtls_ssl_write(ctrl->ssl, ctrl->cache_data, ctrl->cache_len);
    		free(ctrl->cache_data);
    		ctrl->cache_data = NULL;
    		ctrl->cache_len = 0;
    	    if (result < 0)
    	    {
    	    	DBG("%08x", -result);
    			ctrl->need_close = 1;
    			return -1;
    	    }
    	    return 1;
    	}
    	return 0;
#endif
	case EV_NW_SOCKET_CONNECT_OK:
		DBG_ERR("!");
		return 1;
	default:
		return 1;
	}
	return 1;
}

static int network_state_on_line(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if ((ctrl->need_close) || NW_WAIT_OFF_LINE == ctrl->wait_target_state)
	{
		return -1;
	}

	switch(event->ID)
	{
	case EV_NW_RESET:
	case EV_NW_SOCKET_ERROR:
	case EV_NW_SOCKET_REMOTE_CLOSE:
	case EV_NW_SOCKET_CLOSE_OK:
		ctrl->need_close = 1;
		return -1;
	case EV_NW_STATE:
		if (!event->Param2)
		{
			ctrl->need_close = 1;
			return -1;
		}
		break;
	case EV_NW_SOCKET_TX_OK:
		ctrl->ack_size += event->Param2;
		if (NW_WAIT_TX_OK == ctrl->wait_target_state)
		{

			if (ctrl->ack_size == ctrl->tx_size)
			{
				return 0;
			}
		}
		break;
	case EV_NW_SOCKET_RX_NEW:
		ctrl->new_rx_flag = 1;
		if (NW_WAIT_TX_OK != ctrl->wait_target_state)
		{
			return 0;
		}
		break;
	default:
		return 1;
	}
	return 1;
}

static int network_state_listen(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if ((ctrl->need_close) || NW_WAIT_OFF_LINE == ctrl->wait_target_state)
	{
		return -1;
	}
	switch(event->ID)
	{
	case EV_NW_RESET:
	case EV_NW_SOCKET_ERROR:
		ctrl->need_close = 1;
		return -1;
	case EV_NW_SOCKET_REMOTE_CLOSE:
	case EV_NW_SOCKET_CLOSE_OK:
		if (adapter->opt->no_accept)
		{
			if (network_socket_listen(ctrl))
			{
				return -1;
			}
			ctrl->state = NW_STATE_CONNECTING;
			ctrl->wait_target_state = NW_WAIT_ON_LINE;
			return 1;
		}
		else
		{
			break;
		}
	case EV_NW_STATE:
		if (!event->Param2)
		{
			ctrl->need_close = 1;
			return -1;
		}
		break;
	case EV_NW_SOCKET_TX_OK:
		ctrl->ack_size += event->Param2;
		if (NW_WAIT_TX_OK == ctrl->wait_target_state)
		{

			if (ctrl->ack_size == ctrl->tx_size)
			{
				return 0;
			}
		}
		break;
	case EV_NW_SOCKET_RX_NEW:
		ctrl->new_rx_flag = 1;
		if (NW_WAIT_TX_OK != ctrl->wait_target_state)
		{
			return 0;
		}
		break;
	case EV_NW_SOCKET_NEW_CONNECT:
		break;
	default:
		return 1;
	}
	return 1;
}

static int network_state_disconnecting(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	if (ctrl->wait_target_state != NW_WAIT_OFF_LINE)
	{
		return -1;
	}
	switch(event->ID)
	{
	case EV_NW_RESET:
	case EV_NW_SOCKET_ERROR:
	case EV_NW_SOCKET_REMOTE_CLOSE:
	case EV_NW_SOCKET_CLOSE_OK:
		network_force_close_socket(ctrl);
		ctrl->state = NW_STATE_OFF_LINE;
		ctrl->socket_id = -1;
		return 0;
	case EV_NW_STATE:
		if (!event->Param2)
		{
			return -1;
		}
		else
		{
			network_force_close_socket(ctrl);
			ctrl->state = NW_STATE_OFF_LINE;
			ctrl->socket_id = -1;
		}
		break;
	default:
		return 1;
	}
}

typedef int (*network_state_fun)(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter);
static network_state_fun network_state_fun_list[]=
{
		network_state_link_off,
		network_state_off_line,
		network_state_wait_dns,
		network_state_connecting,
		network_state_shakehand,
		network_state_on_line,
		network_state_listen,
		network_state_disconnecting,
};

static void network_default_statemachine(network_ctrl_t *ctrl, OS_EVENT *event, network_adapter_t *adapter)
{
	int result;
	if (ctrl->state > NW_STATE_DISCONNECTING)
	{
		ctrl->state = NW_STATE_LINK_OFF;
		event->Param1 = -1;
		network_force_close_socket(ctrl);
		event->ID = ctrl->wait_target_state + EV_NW_RESULT_BASE;

	}
	else
	{
		result = network_state_fun_list[ctrl->state](ctrl, event, adapter);
		if (result > 0)
		{
			return ;
		}
		event->ID = ctrl->wait_target_state + EV_NW_RESULT_BASE;
		event->Param1 = result;
	}
	ctrl->wait_target_state = NW_WAIT_NONE;
	if (ctrl->task_handle)
	{
		platform_send_event(ctrl->task_handle, event->ID, event->Param1, event->Param2, event->Param3);
	}
	else if (ctrl->user_callback)
	{
		ctrl->user_callback(event, ctrl->user_data);
	}
}


static int32_t network_default_socket_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	luat_network_cb_param_t *cb_param = (luat_network_cb_param_t *)param;
	network_adapter_t *adapter =(network_adapter_t *)(cb_param->param);
	int i;
	network_ctrl_t *ctrl = (network_ctrl_t *)event->Param3;
	NW_LOCK;
	if (event->ID > EV_NW_TIMEOUT)
	{
		if (ctrl && ((ctrl->tag == cb_param->tag) || (event->ID == EV_NW_DNS_RESULT)))
		{
			if (ctrl->auto_mode)
			{
//				DBG("%d,%d,%d", ctrl->socket_id, ctrl->state, ctrl->wait_target_state);
				network_default_statemachine(ctrl, event, adapter);
//				DBG("%d,%d,%d", ctrl->socket_id, ctrl->state, ctrl->wait_target_state);
			}
			else if (ctrl->task_handle)
			{
				platform_send_event(ctrl->task_handle, event->ID, event->Param1, event->Param2, event->Param3);
			}
			else if (ctrl->user_callback)
			{
				ctrl->user_callback(event, ctrl->user_data);
			}
		}
		else
		{
			DBG_ERR("cb ctrl invaild %x", ctrl);
			DBG_HexPrintf(&ctrl->tag, 8);
			DBG_HexPrintf(&cb_param->tag, 8);
		}
	}
	else
	{
		for (i = 0; i < adapter->opt->max_socket_num; i++)
		{
			if (adapter->ctrl_busy[i])
			{
				ctrl = &adapter->ctrl_table[i];
				if (ctrl->auto_mode)
				{
//					DBG("%d,%d,%d", ctrl->socket_id, ctrl->state, ctrl->wait_target_state);
					network_default_statemachine(ctrl, event, adapter);
//					DBG("%d,%d,%d", ctrl->socket_id, ctrl->state, ctrl->wait_target_state);
				}
				else if (ctrl->task_handle)
				{
					platform_send_event(ctrl->task_handle, event->ID, event->Param1, event->Param2, event->Param3);
				}
				else if (ctrl->user_callback)
				{
					ctrl->user_callback(event, ctrl->user_data);
				}
			}
		}
	}
	NW_UNLOCK;
	return 0;
}

static int32_t network_default_timer_callback(void *data, void *param)
{
	platform_send_event(param, EV_NW_TIMEOUT, 0, 0, 0);
	return 0;
}

uint8_t network_string_is_ipv4(const char *string, uint32_t len)
{
	int i;
	for(i = 0; i < len; i++)
	{
		if (!isdigit(string[i]) && (string[i] != '.'))
		{
			return 0;
		}
	}
	return 1;
}

uint32_t network_string_to_ipv4(const char *string, uint32_t len)
{
	int i;
	int8_t Buf[4][4];
	CmdParam CP;
	PV_Union uIP;
	char temp[32];
	memset(Buf, 0, sizeof(Buf));
	CP.param_max_len = 4;
	CP.param_max_num = 4;
	CP.param_num = 0;
	CP.param_str = (int8_t *)Buf;
	memcpy(temp, string, len);
	temp[len] = 0;
	CmdParseParam(temp, &CP, '.');
	for(i = 0; i < 4; i++)
	{
		uIP.u8[i] = strtol(Buf[i], NULL, 10);
	}
//	DBG("%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
	return uIP.u32;
}

#define SWAP(x) ((((x) & (uint32_t)0x000000ffUL) << 24) | \
                     (((x) & (uint32_t)0x0000ff00UL) <<  8) | \
                     (((x) & (uint32_t)0x00ff0000UL) >>  8) | \
                     (((x) & (uint32_t)0xff000000UL) >> 24))

int network_string_to_ipv6(const char *string, luat_ip_addr_t *ip_addr)
{


  uint32_t addr_index, zero_blocks, current_block_index, current_block_value;
  const char *s;
  ip_addr->is_ipv6 = 0xff;
  /* Count the number of colons, to count the number of blocks in a "::" sequence
	 zero_blocks may be 1 even if there are no :: sequences */
  zero_blocks = 8;
  for (s = string; *s != 0; s++) {
	if (*s == ':') {
	  zero_blocks--;
	} else if (!isxdigit(*s)) {
	  break;
	}
  }

  /* parse each block */
  addr_index = 0;
  current_block_index = 0;
  current_block_value = 0;
  for (s = string; *s != 0; s++) {
	if (*s == ':') {
		if (current_block_index & 0x1) {
			ip_addr->ipv6_u32_addr[addr_index++] |= current_block_value;
		}
		else {
			ip_addr->ipv6_u32_addr[addr_index] = current_block_value << 16;
		}
	  current_block_index++;
	  current_block_value = 0;
	  if (current_block_index > 7) {
		/* address too long! */
		return 0;
	  }
	  if (s[1] == ':') {
		if (s[2] == ':') {
		  /* invalid format: three successive colons */
		  return 0;
		}
		s++;
		/* "::" found, set zeros */
		while (zero_blocks > 0) {
		  zero_blocks--;
		  if (current_block_index & 0x1) {
			addr_index++;
		  } else {
			  ip_addr->ipv6_u32_addr[addr_index] = 0;
		  }
		  current_block_index++;
		  if (current_block_index > 7) {
			/* address too long! */
			return 0;
		  }
		}
	  }
	} else if (isxdigit(*s)) {
	  /* add current digit */
	  current_block_value = (current_block_value << 4) +
		  (isxdigit(*s) ? (uint32_t)(*s - '0') :
		  (uint32_t)(10 + (isxdigit(*s) ? *s - 'a' : *s - 'A')));
	} else {
	  /* unexpected digit, space? CRLF? */
	  break;
	}
  }


	if (current_block_index & 0x1) {
		ip_addr->ipv6_u32_addr[addr_index++] |= current_block_value;
	}
	else {
		ip_addr->ipv6_u32_addr[addr_index] = current_block_value << 16;
	}

	/* convert to network byte order. */
	for (addr_index = 0; addr_index < 4; addr_index++) {
		ip_addr->ipv6_u32_addr[addr_index] = SWAP(ip_addr->ipv6_u32_addr[addr_index]);
	}



	if (current_block_index != 7) {

		return 0;
	}
	ip_addr->is_ipv6 = 1;
	return 1;

}

int network_get_last_register_adapter(void)
{
	return prv_network.last_adapter_index;
}

int network_register_adapter(uint8_t adapter_index, network_adapter_info *info, void *user_data)
{
	prv_adapter_table[adapter_index].opt = info;
	prv_adapter_table[adapter_index].user_data = user_data;
	info->socket_set_callback(network_default_socket_callback, &prv_adapter_table[adapter_index], user_data);
	prv_adapter_table[adapter_index].ctrl_table = zalloc((info->max_socket_num) * sizeof(network_ctrl_t));
	prv_adapter_table[adapter_index].ctrl_busy = zalloc(info->max_socket_num);
	prv_adapter_table[adapter_index].port = 60000;
	if (!prv_network.is_init)
	{
		INIT_LLIST_HEAD(&prv_network.dns_cache_head);
		prv_network.is_init = 0;
	}

	prv_network.last_adapter_index = adapter_index;
}

void network_set_dns_server(uint8_t adapter_index, uint8_t server_index, luat_ip_addr_t *ip)
{
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	adapter->opt->set_dns_server(server_index, ip, adapter->user_data);
}

/*
 * 申请一个network_ctrl
 */
network_ctrl_t *network_alloc_ctrl(uint8_t adapter_index)
{
	int i;
	network_ctrl_t *ctrl = NULL;
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	NW_LOCK;
	for (i = 0; i < adapter->opt->max_socket_num; i++)
	{
		if (!adapter->ctrl_busy[i])
		{

			adapter->ctrl_busy[i] = 1;
			ctrl = &adapter->ctrl_table[i];
			ctrl->adapter_index = adapter_index;
			break;
		}
	}
	if (i >= adapter->opt->max_socket_num) {DBG_ERR("adapter no more ctrl!");}
	NW_UNLOCK;
	return ctrl;
}

/*
 * 归还一个network_ctrl
 */
void network_release_ctrl(network_ctrl_t *ctrl)
{
	int i;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	NW_LOCK;
	for (i = 0; i < adapter->opt->max_socket_num; i++)
	{
		if (&adapter->ctrl_table[i] == ctrl)
		{
			network_deinit_tls(ctrl);
			if (ctrl->timer)
			{
				platform_release_timer(ctrl->timer);
			}
			if (ctrl->cache_data)
			{
				free(ctrl->cache_data);
				ctrl->cache_data = NULL;
			}
			if (ctrl->dns_ip)
			{
				free(ctrl->dns_ip);
				ctrl->dns_ip = NULL;
			}
			adapter->ctrl_busy[i] = 0;
			break;
		}
	}
	NW_UNLOCK;
	if (i >= adapter->opt->max_socket_num) {DBG_ERR("adapter index maybe error!, %d, %x", ctrl->adapter_index, ctrl);}

}

void network_init_ctrl(network_ctrl_t *ctrl, HANDLE task_handle, CBFuncEx_t callback, void *param)
{
	uint8_t adapter_index = ctrl->adapter_index;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	memset(ctrl, 0, sizeof(network_ctrl_t));
	ctrl->adapter_index = adapter_index;
	ctrl->task_handle = task_handle;
	ctrl->user_callback = callback;
	ctrl->user_data = param;
	ctrl->socket_id = -1;
	ctrl->socket_param = ctrl;
	ctrl->remote_ip.is_ipv6 = 0xff;
	if (task_handle)
	{
		ctrl->timer = platform_create_timer(network_default_timer_callback, task_handle, NULL);
	}
}

void network_set_base_mode(network_ctrl_t *ctrl, uint8_t is_tcp, uint32_t tcp_timeout_ms, uint8_t keep_alive, uint32_t keep_idle, uint8_t keep_interval, uint8_t keep_cnt)
{
	ctrl->is_tcp = is_tcp;
	ctrl->tcp_keep_alive = keep_alive;
	ctrl->tcp_keep_idle = keep_idle;
	ctrl->tcp_keep_interval = keep_interval;
	ctrl->tcp_keep_cnt = keep_cnt;
	ctrl->tcp_timeou_ms = tcp_timeout_ms;
}

int network_set_local_port(network_ctrl_t *ctrl, uint16_t local_port)
{
	int i;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (local_port)
	{
		NW_LOCK;
		for (i = 0; i < adapter->opt->max_socket_num; i++)
		{
			if (&adapter->ctrl_table[i] != ctrl)
			{
				if (adapter->ctrl_table[i].local_port == local_port)
				{
					NW_UNLOCK;
					return -1;
				}
			}

		}
		ctrl->local_port = local_port;
		NW_UNLOCK;
		return 0;
	}
	else
	{
		NW_LOCK;
		adapter->port++;
		if (adapter->port < 60000)
		{
			adapter->port = 60000;
		}
		ctrl->local_port = adapter->port;
		NW_UNLOCK;
		return 0;
	}
}

uint8_t network_check_ready(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->check_ready(adapter->user_data);
}

int network_create_soceket(network_ctrl_t *ctrl, uint8_t is_ipv6)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->socket_id = adapter->opt->create_soceket(ctrl->is_tcp, &ctrl->tag, ctrl->socket_param, is_ipv6, adapter->user_data);
	if (ctrl->socket_id < 0)
	{
		ctrl->tag = 0;
		return -1;
	}
	return 0;
}

int network_socket_connect(network_ctrl_t *ctrl, luat_ip_addr_t *remote_ip)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->is_server_mode = 0;
	ctrl->online_ip = remote_ip;
	return adapter->opt->socket_connect(ctrl->socket_id, ctrl->tag, ctrl->local_port, remote_ip, ctrl->remote_port, adapter->user_data);
}

int network_socket_listen(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->is_server_mode = 1;
	return adapter->opt->socket_listen(ctrl->socket_id, ctrl->tag, ctrl->local_port, adapter->user_data);
}

//作为server接受一个client
//成功返回0，失败 < 0
int network_socket_accept(network_ctrl_t *ctrl, network_ctrl_t *accept_ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (adapter->opt->no_accept)
	{
		return 0;
	}
	accept_ctrl->socket_id = adapter->opt->socket_accept(ctrl->socket_id, ctrl->tag, &accept_ctrl->remote_ip, &accept_ctrl->remote_port, adapter->user_data);
	if (accept_ctrl->socket_id < 0)
	{
		return -1;
	}
	else
	{
		return 0;
	}
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
//成功返回0，失败 < 0
int network_socket_disconnect(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		return adapter->opt->socket_disconnect(ctrl->socket_id, ctrl->tag, adapter->user_data);
	}
	return 0;
}
//释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_close(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		return adapter->opt->socket_close(ctrl->socket_id, ctrl->tag, adapter->user_data);
	}
	return 0;
}
//强行释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_force_close(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		adapter->opt->socket_force_close(ctrl->socket_id, adapter->user_data);
	}
	ctrl->socket_id = -1;
	return 0;
}
//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
//udp时，只返回1个block数据，需要多次读直到没有数据为止
//成功返回实际读取的值，失败 < 0
int network_socket_receive(network_ctrl_t *ctrl,uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->socket_receive(ctrl->socket_id, ctrl->tag, buf, len, flags, remote_ip, remote_port, adapter->user_data);
}
//tcp时，不需要remote_ip和remote_port
//成功返回0，失败 < 0
int network_socket_send(network_ctrl_t *ctrl,const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->socket_send(ctrl->socket_id, ctrl->tag, buf, len, flags, remote_ip, remote_port, adapter->user_data);
}

int network_getsockopt(network_ctrl_t *ctrl, int level, int optname, void *optval, uint32_t *optlen)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->getsockopt(ctrl->socket_id, ctrl->tag, level, optname, optval, optlen, adapter->user_data);
}
int network_setsockopt(network_ctrl_t *ctrl, int level, int optname, const void *optval, uint32_t optlen)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->setsockopt(ctrl->socket_id, ctrl->tag, level, optname, optval, optlen, adapter->user_data);
}
//非posix的socket，用这个根据实际硬件设置参数
int network_user_cmd(network_ctrl_t *ctrl,  uint32_t cmd, uint32_t value)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->user_cmd(ctrl->socket_id, ctrl->tag, cmd, value, adapter->user_data);
}

int network_dns(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];

	return adapter->opt->dns(ctrl->domain_name, ctrl->domain_name_len, ctrl, adapter->user_data);
}

int network_get_local_ip_info(network_ctrl_t *ctrl, luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->get_local_ip_info(ip, submask, gateway, adapter->user_data);
}

void network_force_close_socket(network_ctrl_t *ctrl)
{
#ifdef LUAT_USE_TLS
	if (ctrl->tls_mode)
	{
		mbedtls_ssl_free(ctrl->ssl);
	}
#endif
	if (network_socket_close(ctrl))
	{
		network_clean_invaild_socket(ctrl->adapter_index);
		network_socket_force_close(ctrl);
	}
	ctrl->need_close = 0;
	ctrl->socket_id = -1;
	if (ctrl->dns_ip)
	{
		free(ctrl->dns_ip);
		ctrl->dns_ip = NULL;
	}
	ctrl->dns_ip_cnt = 0;
	ctrl->dns_ip_nums = 0;
}

void network_clean_invaild_socket(uint8_t adapter_index)
{
	int i;
	int *list;
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	network_ctrl_t *ctrl;
	list = malloc(adapter->opt->max_socket_num * sizeof(int));
	NW_LOCK;
	for (i = 0; i < adapter->opt->max_socket_num; i++)
	{
		ctrl = &adapter->ctrl_table[i];
		if (!adapter->opt->socket_check(ctrl->socket_id, ctrl->tag, adapter->user_data))
		{
			list[i] = ctrl->socket_id;
		}
		else
		{
			ctrl->socket_id = -1;
			list[i] = -1;
		}
		DBG("%d,%d", i, list[i]);
	}
	adapter->opt->socket_clean(list, adapter->opt->max_socket_num, adapter->user_data);
	NW_UNLOCK;
	free(list);
}


#ifdef LUAT_USE_TLS
static int tls_verify(void *ctx, mbedtls_x509_crt *crt, int Index, uint32_t *result)
{
	network_ctrl_t *ctrl = (network_ctrl_t *)ctx;
	DBG("%d, %08x", Index, *result);
	return 0;
}
#endif
int network_set_psk_info(network_ctrl_t *ctrl,
		const unsigned char *psk, size_t psk_len,
		const unsigned char *psk_identity, size_t psk_identity_len)
{
#ifdef LUAT_USE_TLS
	if (!ctrl->tls_mode)
	{
		return -ERROR_PERMISSION_DENIED;
	}

//	DBG("%.*s, %.*s", psk_len, psk, psk_identity_len, psk_identity);
	int ret = mbedtls_ssl_conf_psk( ctrl->config,
			psk, psk_len, psk_identity, psk_identity_len );
	if (ret != 0)
	{
		DBG("0x%x", -ret);
		return -ERROR_OPERATION_FAILED;
	}
	return ERROR_NONE;
#else
	return -1;
#endif
}

int network_set_server_cert(network_ctrl_t *ctrl, const unsigned char *cert, size_t cert_len)
{
#ifdef LUAT_USE_TLS
	int ret;
	if (!ctrl->tls_mode)
	{
		return -ERROR_PERMISSION_DENIED;
	}
    ret = mbedtls_x509_crt_parse( ctrl->ca_cert, cert, cert_len);
	if (ret != 0)
	{
		DBG("%08x", -ret);
		return -ERROR_OPERATION_FAILED;
	}

	return ERROR_NONE;
#else
	return -1;
#endif
}

int network_set_client_cert(network_ctrl_t *ctrl,
		const unsigned char *cert, size_t certLen,
        const unsigned char *key, size_t keylen,
        const unsigned char *pwd, size_t pwdlen)
{
#ifdef LUAT_USE_TLS
	int ret;
	mbedtls_x509_crt *client_cert = NULL;
	mbedtls_pk_context *pkey = NULL;
	if (!ctrl->tls_mode)
	{
		return -ERROR_PERMISSION_DENIED;
	}
	client_cert = zalloc(sizeof(mbedtls_x509_crt));
	pkey = zalloc(sizeof(mbedtls_pk_context));
	if (!client_cert || !pkey)
	{
		goto ERROR_OUT;
	}
    ret = mbedtls_x509_crt_parse( client_cert, cert, certLen );
    if (ret != 0)
    {
    	DBG("%08x", -ret);
    	goto ERROR_OUT;
    }
    ret = mbedtls_pk_parse_key( pkey, key, keylen, pwd, pwdlen );
    if (ret != 0)
    {
		DBG("%08x", -ret);
		goto ERROR_OUT;
    }
    ret = mbedtls_ssl_conf_own_cert( ctrl->config, client_cert, pkey );
    if (ret != 0)
    {
		DBG("%08x", -ret);
		goto ERROR_OUT;
    }
    return ERROR_NONE;
ERROR_OUT:
	if (client_cert) free(client_cert);
	if (pkey) free(pkey);
	return -1;
#else
	return -1;
#endif
}

int network_cert_verify_result(network_ctrl_t *ctrl)
{
#ifdef LUAT_USE_TLS
	if (!ctrl->tls_mode)
	{
		return -1;
	}
	return mbedtls_ssl_get_verify_result(ctrl->ssl);
#else
	return -1;
#endif
}

static int tls_random( void *p_rng,
        unsigned char *output, size_t output_len )
{
	platform_random(output, output_len);
	return 0;
}

void network_init_tls(network_ctrl_t *ctrl, int verify_mode)
{
#ifdef LUAT_USE_TLS
	ctrl->tls_mode = 1;
	if (!ctrl->ssl)
	{
		ctrl->ssl = zalloc(sizeof(mbedtls_ssl_context));
		ctrl->ca_cert = zalloc(sizeof(mbedtls_x509_crt));
		ctrl->config = zalloc(sizeof(mbedtls_ssl_config));
		mbedtls_ssl_config_defaults( ctrl->config, MBEDTLS_SSL_IS_CLIENT, ctrl->is_tcp?MBEDTLS_SSL_TRANSPORT_STREAM:MBEDTLS_SSL_TRANSPORT_DATAGRAM, MBEDTLS_SSL_PRESET_DEFAULT);
		ctrl->config->authmode = verify_mode;
		ctrl->config->hs_timeout_min = 20000;
		ctrl->config->f_rng = tls_random;
		ctrl->config->p_rng = NULL;
		ctrl->config->f_dbg = tls_dbg;
		ctrl->config->p_dbg = NULL;
		ctrl->config->f_vrfy = tls_verify;
		ctrl->config->p_vrfy = ctrl;
		ctrl->config->ca_chain = ctrl->ca_cert;
		ctrl->config->read_timeout = 20000;
	    ctrl->tls_long_timer = platform_create_timer(tls_longtimeout, ctrl, NULL);
	    ctrl->tls_short_timer = platform_create_timer(tls_shorttimeout, ctrl, NULL);
	}
	ctrl->tls_timer_state = -1;
#endif
}

void network_deinit_tls(network_ctrl_t *ctrl)
{
#ifdef LUAT_USE_TLS
	if (ctrl->ssl)
	{
		mbedtls_ssl_free(ctrl->ssl);
		free(ctrl->ssl);
		ctrl->ssl = NULL;
	}

	if (ctrl->config)
	{
		mbedtls_ssl_config_free(ctrl->config);
		free(ctrl->config);
		ctrl->config = NULL;
	}

	if (ctrl->ca_cert)
	{
		mbedtls_x509_crt_free(ctrl->ca_cert);
		free(ctrl->ca_cert);
		ctrl->ca_cert = NULL;
	}

	ctrl->tls_mode = 0;
	ctrl->tls_timer_state = -1;
	if (ctrl->tls_short_timer)
	{
		platform_release_timer(ctrl->tls_short_timer);
		ctrl->tls_short_timer = NULL;
	}
	if (ctrl->tls_long_timer)
	{
		platform_release_timer(ctrl->tls_long_timer);
		ctrl->tls_long_timer = NULL;
	}
#endif
}

int network_wait_link_up(network_ctrl_t *ctrl, uint32_t timeout_ms)
{
	NW_LOCK;
	ctrl->auto_mode = 1;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (network_check_ready(ctrl))
	{
		ctrl->state = NW_STATE_OFF_LINE;
		ctrl->wait_target_state = NW_WAIT_NONE;
		NW_UNLOCK;
		return 0;
	}
	ctrl->state = NW_STATE_LINK_OFF;
	ctrl->wait_target_state = NW_WAIT_LINK_UP;

	NW_UNLOCK;
	if (!ctrl->task_handle || !timeout_ms)
	{
		return 1;
	}
	uint8_t finish = 0;
	OS_EVENT event;
	int result;
	//DBG_INFO("%s wait for active!,%u,%x", Net->Tag, To * SYS_TICK, Net->hTask);

	platform_start_timer(ctrl->timer, timeout_ms, 0);
	while (!finish)
	{
		platform_wait_event(ctrl->task_handle, 0, &event, NULL, 0);
		switch (event.ID)
		{
		case EV_NW_RESULT_LINK:
			result = (int)event.Param1;
			finish = 1;
			break;
		case EV_NW_TIMEOUT:
			result = -1;
			finish = 1;
			break;
		default:
			if (ctrl->user_callback)
			{
				ctrl->user_callback((void *)&event, ctrl->task_handle);
			}
			break;
		}
	}
	platform_stop_timer(ctrl->timer);
	return result;
}
/*
 * 1.进行ready检测和等待ready
 * 2.有remote_ip则开始连接服务器并等待连接结果
 * 3.没有remote_ip则开始对url进行dns解析，解析完成后对所有ip进行尝试连接直到有个成功或者全部失败
 * 4.如果是加密模式，还要走握手环节，等到握手环节完成后才能返回结果
 * local_port如果为0则api内部自动生成一个
 */
int network_connect(network_ctrl_t *ctrl, const char *domain_name, uint32_t domain_name_len, luat_ip_addr_t *remote_ip, uint16_t remote_port, uint32_t timeout_ms)
{
	if (ctrl->socket_id >= 0)
	{
		return -1;
	}

	NW_LOCK;
	if (ctrl->dns_ip)
	{
		free(ctrl->dns_ip);
		ctrl->dns_ip = NULL;
	}
	if (ctrl->cache_data)
	{
		free(ctrl->cache_data);
		ctrl->cache_data = NULL;
	}
	ctrl->need_close = 0;
	ctrl->domain_name = domain_name;
	ctrl->domain_name_len = domain_name_len;
	if (remote_ip)
	{
		ctrl->remote_ip = *remote_ip;
	}
	else
	{
		ctrl->remote_ip.is_ipv6 = 0xff;
	}
	ctrl->auto_mode = 1;
	ctrl->remote_port = remote_port;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->wait_target_state = NW_WAIT_ON_LINE;
	if (!network_check_ready(ctrl))
	{

		ctrl->state = NW_STATE_LINK_OFF;
		goto NETWORK_CONNECT_WAIT;
	}
	if (network_prepare_connect(ctrl))
	{
		ctrl->state = NW_STATE_OFF_LINE;
		ctrl->wait_target_state = NW_WAIT_NONE;
		NW_UNLOCK;
		return -1;
	}
NETWORK_CONNECT_WAIT:
	NW_UNLOCK;
	if (!ctrl->task_handle || !timeout_ms)
	{

		return 1;
	}
	uint8_t finish = 0;
	OS_EVENT event;
	int result;
	//DBG_INFO("%s wait for active!,%u,%x", Net->Tag, To * SYS_TICK, Net->hTask);

	platform_start_timer(ctrl->timer, timeout_ms, 0);
	while (!finish)
	{
		platform_wait_event(ctrl->task_handle, 0, &event, NULL, 0);
		switch (event.ID)
		{
		case EV_NW_RESULT_CONNECT:
			result = (int)event.Param1;
			finish = 1;
			break;
		case EV_NW_TIMEOUT:
			result = -1;
			finish = 1;
			break;
		default:
			if (ctrl->user_callback)
			{
				ctrl->user_callback((void *)&event, ctrl->task_handle);
			}
			break;
		}
	}
	platform_stop_timer(ctrl->timer);
	return result;
}

int network_listen(network_ctrl_t *ctrl, uint16_t local_port, uint32_t timeout_ms)
{
	ctrl->auto_mode = 1;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
}

int network_close(network_ctrl_t *ctrl, uint32_t timeout_ms)
{
	NW_LOCK;
	if (ctrl->cache_data)
	{
		free(ctrl->cache_data);
		ctrl->cache_data = NULL;
	}
	uint8_t old_state = ctrl->state;
	ctrl->auto_mode = 1;
	ctrl->need_close = 0;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
#ifdef LUAT_USE_TLS
	if (ctrl->tls_mode)
	{
		mbedtls_ssl_free(ctrl->ssl);
	}
#endif
	if (ctrl->socket_id < 0)
	{

		ctrl->state = NW_STATE_OFF_LINE;
		ctrl->wait_target_state = NW_WAIT_NONE;
		NW_UNLOCK;
		return 0;
	}

	ctrl->state = NW_STATE_DISCONNECTING;
	ctrl->wait_target_state = NW_WAIT_OFF_LINE;

	if ((NW_STATE_ONLINE == old_state) && ctrl->is_tcp)
	{
		if (network_socket_disconnect(ctrl))
		{
			network_force_close_socket(ctrl);
			ctrl->state = NW_STATE_OFF_LINE;
			ctrl->wait_target_state = NW_WAIT_NONE;
			NW_UNLOCK;
			return 0;
		}
	}
	else
	{
		network_force_close_socket(ctrl);
		ctrl->state = NW_STATE_OFF_LINE;
		ctrl->wait_target_state = NW_WAIT_NONE;
		NW_UNLOCK;
		return 0;
	}
	NW_UNLOCK;
	if (!ctrl->task_handle || !timeout_ms)
	{
		return 1;
	}
	uint8_t finish = 0;
	OS_EVENT event;
	int result;
	//DBG_INFO("%s wait for active!,%u,%x", Net->Tag, To * SYS_TICK, Net->hTask);

	platform_start_timer(ctrl->timer, timeout_ms, 0);
	while (!finish)
	{
		platform_wait_event(ctrl->task_handle, 0, &event, NULL, 0);
		switch (event.ID)
		{
		case EV_NW_RESULT_CLOSE:
			result = 0;
			finish = 1;
			break;
		case EV_NW_TIMEOUT:
			result = 0;
			finish = 1;
			break;
		default:
			if (ctrl->user_callback)
			{
				ctrl->user_callback((void *)&event, ctrl->task_handle);
			}
			break;
		}
	}
	platform_stop_timer(ctrl->timer);
	network_socket_force_close(ctrl);
	return result;
}
/*
 * timeout_ms=0时，为非阻塞接口
 */
int network_tx(network_ctrl_t *ctrl, const uint8_t *data, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, uint32_t *tx_len, uint32_t timeout_ms)
{
	if ((ctrl->need_close) || (ctrl->socket_id < 0) || (ctrl->state != NW_STATE_ONLINE))
	{
		return -1;
	}
	NW_LOCK;
	int result;

	ctrl->auto_mode = 1;
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
#ifdef LUAT_USE_TLS
	if (ctrl->tls_mode)
	{
		if (ctrl->tls_need_reshakehand)
		{
			ctrl->tls_need_reshakehand = 0;
			if (ctrl->cache_data)
			{
				free(ctrl->cache_data);
				ctrl->cache_data = NULL;
			}
			ctrl->cache_data = malloc(len);
			memcpy(ctrl->cache_data, data, len);
			ctrl->cache_len = len;
	    	mbedtls_ssl_session_reset(ctrl->ssl);
	    	do
	    	{
	    		result = mbedtls_ssl_handshake_step( ctrl->ssl );
	    		switch(result)
	    		{
	    		case MBEDTLS_ERR_SSL_WANT_READ:
	    			ctrl->state = NW_STATE_SHAKEHAND;
	    			goto NETWORK_TX_WAIT;
	    		case 0:
	    			break;
	    		default:
	    			DBG_ERR("0x%x, %d", -result, ctrl->ssl->state);
	    			ctrl->need_close = 1;
	    			NW_UNLOCK;
	    			return -1;
	    		}
	    	}while(ctrl->ssl->state != MBEDTLS_SSL_HANDSHAKE_OVER);
		}
		result = mbedtls_ssl_write(ctrl->ssl, data, len);
	    if (result < 0)
	    {
	    	DBG("%08x", -result);
			ctrl->need_close = 1;
			NW_UNLOCK;
			return -1;
	    }
	}
	else
#endif
	{
		result = network_base_tx(ctrl, data, len, flags, remote_ip, remote_port);
		if (result < 0)
		{
			ctrl->need_close = 1;
			NW_UNLOCK;
			return -1;
		}
		*tx_len = result;
		if (!result && len)
		{
			NW_UNLOCK;
			return 0;
		}
	}

NETWORK_TX_WAIT:
	ctrl->wait_target_state = NW_WAIT_TX_OK;
	NW_UNLOCK;

	if (!ctrl->task_handle || !timeout_ms)
	{
		return 1;
	}
	uint8_t finish = 0;
	OS_EVENT event;
	//DBG_INFO("%s wait for active!,%u,%x", Net->Tag, To * SYS_TICK, Net->hTask);

	platform_start_timer(ctrl->timer, timeout_ms, 0);
	while (!finish)
	{
		platform_wait_event(ctrl->task_handle, 0, &event, NULL, 0);
		switch (event.ID)
		{
		case EV_NW_RESULT_TX:
			result = (int)event.Param1;
			if (!result)
			{
				result = -1;
			}
			finish = 1;
			break;
		case EV_NW_TIMEOUT:
			result = -1;
			finish = 1;
			break;
		default:
			if (ctrl->user_callback)
			{
				ctrl->user_callback((void *)&event, ctrl->task_handle);
			}
			break;
		}
	}
	platform_stop_timer(ctrl->timer);
	return result;
}
/*
 * 实际读到的数据量在rx_len里，如果是UDP模式且为server时，需要看remote_ip和remote_port
 */
int network_rx(network_ctrl_t *ctrl, uint8_t *data, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, uint32_t *rx_len)
{
	if ((ctrl->need_close) || (ctrl->socket_id < 0) || (ctrl->state != NW_STATE_ONLINE))
	{
		return -1;
	}
	NW_LOCK;
	int result = -1;
	ctrl->auto_mode = 1;
	if (ctrl->new_rx_flag)
	{
		if (data)
		{
			ctrl->new_rx_flag = 0;
	#ifdef LUAT_USE_TLS
			if (ctrl->tls_mode)
			{
				uint32_t read_len = 0;
				uint8_t is_error = 0;
				do
				{
					result = mbedtls_ssl_read(ctrl->ssl, data + read_len, len - read_len);
					if (result < 0 && (result != MBEDTLS_ERR_SSL_WANT_READ))
					{
						is_error = 1;
						break;
					}
					else
					{
						read_len += result;
					}
				}while(network_socket_receive(ctrl, NULL, len, flags, remote_ip, remote_port) > 0);

				if ( !is_error )
				{
					result = read_len;
				}
				else
				{
					result = -1;
				}
			}
			else
	#endif
			{

				result = network_socket_receive(ctrl, data, len, flags, remote_ip, remote_port);
			}
		}
		else
		{
			result = network_socket_receive(ctrl, data, len, flags, remote_ip, remote_port);
		}
	}
	else
	{
		result = 0;
	}
	NW_UNLOCK;
	if (result >= 0)
	{
		*rx_len = result;
		return 0;
	}
	else
	{
		return -1;
	}
}

int network_wait_event(network_ctrl_t *ctrl, OS_EVENT *out_event, uint32_t timeout_ms, uint8_t *is_timeout)
{
	if ((ctrl->need_close) || (ctrl->socket_id < 0) || (ctrl->state != NW_STATE_ONLINE))
	{
		return -1;
	}
	if (ctrl->new_rx_flag)
	{
		return 0;
	}
	NW_LOCK;
	ctrl->auto_mode = 1;
	ctrl->wait_target_state = NW_WAIT_EVENT;
	NW_UNLOCK;
	if (!ctrl->task_handle || !timeout_ms)
	{
		return 1;
	}
	*is_timeout = 0;
	uint8_t finish = 0;
	OS_EVENT event;
	int result;
	//DBG_INFO("%s wait for active!,%u,%x", Net->Tag, To * SYS_TICK, Net->hTask);

	platform_start_timer(ctrl->timer, timeout_ms, 0);
	while (!finish)
	{
		platform_wait_event(ctrl->task_handle, 0, &event, NULL, 0);
		switch (event.ID)
		{
		case EV_NW_RESULT_EVENT:
			result = (int)event.Param1;
			if (result)
			{
				result = -1;
			}
			finish = 1;
			break;
		case EV_NW_TIMEOUT:
			*is_timeout = 1;
			result = 0;
			finish = 1;
			break;
		case EV_NW_BREAK_WAIT:
			if (out_event)
			{
				*out_event = event;
			}
			result = 0;
			finish = 1;
			break;
		default:
			if (out_event)
			{
				*out_event = event;
				result = 0;
				finish = 1;
				break;
			}
			else if (ctrl->user_callback)
			{
				ctrl->user_callback((void *)&event, ctrl->task_handle);
			}
			break;
		}
	}
	platform_stop_timer(ctrl->timer);
	return result;
}
#endif