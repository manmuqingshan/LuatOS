#ifndef LUAT_WLAN_H
#define LUAT_WLAN_H

#include "luat_base.h"
#ifdef __LUATOS__
#include "luat_msgbus.h"
#include "luat_mem.h"
#endif
typedef struct luat_wlan_config
{
    uint32_t mode;
}luat_wlan_config_t;

typedef struct luat_wlan_conninfo
{
    char ssid[36];
    char password[64];
    char bssid[8];
    uint32_t authmode;
    uint32_t auto_reconnection;
    uint32_t auto_reconnection_delay_sec;
}luat_wlan_conninfo_t;

typedef struct luat_wlan_apinfo
{
    char ssid[36];
    char password[64];
    uint8_t gateway[4];
    uint8_t netmask[4];
    uint8_t channel;
    uint8_t encrypt;
    uint8_t hidden;
    uint8_t max_conn;
}luat_wlan_apinfo_t;

enum LUAT_WLAN_MODE {
    LUAT_WLAN_MODE_NULL,
    LUAT_WLAN_MODE_STA,
    LUAT_WLAN_MODE_AP,
    LUAT_WLAN_MODE_APSTA,
    LUAT_WLAN_MODE_MAX
};


enum LUAT_WLAN_ENCRYPT_MODE {
    LUAT_WLAN_ENCRYPT_AUTO,
    LUAT_WLAN_ENCRYPT_NONE,
    LUAT_WLAN_ENCRYPT_WPA,
    LUAT_WLAN_ENCRYPT_WPA2
};

typedef enum LUAT_EVENT_MODULE {
	LUAT_WLAN_EVENT_MOD_WIFI_INTERNAL,   /**< WiFi internal event */
	LUAT_WLAN_EVENT_MOD_WIFI,            /**< WiFi public event */
	LUAT_WLAN_EVENT_MOD_NETIF,           /**< Netif event */
	LUAT_WLAN_EVENT_MOD_COUNT,           /**< Event module count */
} luat_event_module_t;

/**
 * @brief WiFi public event type
 */
typedef enum LUAT_WIFI_EVENT {
	LUAT_WLAN_EVENT_WIFI_SCAN_DONE = 0,      /**< WiFi scan done event */
	LUAT_WLAN_EVENT_WIFI_CSI_DATA_IND,
	LUAT_WLAN_EVENT_WIFI_CSI_ALG_IND,

	LUAT_WLAN_EVENT_WIFI_STA_CONNECTED,      /**< The BK STA is connected */
	LUAT_WLAN_EVENT_WIFI_STA_DISCONNECTED,   /**< The BK STA is disconnected */

	LUAT_WLAN_EVENT_WIFI_AP_CONNECTED,       /**< A STA is connected to the BK AP */
	LUAT_WLAN_EVENT_WIFI_AP_DISCONNECTED,    /**< A STA is disconnected from the BK AP */

	LUAT_WLAN_EVENT_WIFI_NETWORK_FOUND,      /**< The BK STA find target AP */
	LUAT_WLAN_EVENT_WIFI_COUNT,              /**< WiFi event count */
} luat_wifi_event_t;

typedef enum LUAT_WIFI_COUNTRY_POLICY {
	LUAT_WLAN_WIFI_COUNTRY_POLICY_AUTO,   /**< Country policy is auto, use the country info of AP to which the station is connected */
	LUAT_WLAN_WIFI_COUNTRY_POLICY_MANUAL, /**< Country policy is manual, always use the configured country info */
} luat_wifi_country_policy_t;     

typedef struct luat_wifi_country
{
	char                  cc[3];          /**< country code string */
	uint8_t               schan;          /**< start channel */
	uint8_t               nchan;          /**< total channel number */
	int8_t                max_tx_power;   /**< maximum tx power */
	luat_wifi_country_policy_t policy;         /**< country policy */
} luat_wifi_country_t;

typedef struct luat_wifi_event_scan_done
{
	uint32_t scan_id; /**< Scan ID */
	uint32_t scan_use_time;/**< scan time. us */
} luat_wifi_event_scan_done_t;

typedef struct luat_wifi_event_network_found
{
	char    ssid[33];      /**< SSID found to be connected */
	uint8_t bssid[6];        /**< BSSID found to be connected */
} luat_wifi_event_network_found_t;

typedef struct luat_wifi_event_sta_connected
{
	char    ssid[33];      /**< SSID of connected AP */
	uint8_t bssid[6];        /**< BSSID of connected AP*/
} luat_wifi_event_sta_connected_t;

typedef struct luat_wifi_event_sta_disconnected
{
	int disconnect_reason;                /**< Disconnect reason of BK STA */
	uint8_t local_generated;                 /**< if disconnect is request by local */
} luat_wifi_event_sta_disconnected_t;

typedef struct luat_wifi_event_ap_connected
{
	uint8_t mac[6];            /**< MAC of the STA connected to the BK AP */
} luat_wifi_event_ap_connected_t;

typedef struct luat_wifi_event_ap_disconnected
{
	uint8_t mac[6];            /**< MAC of the STA disconnected from the BK AP */
} luat_wifi_event_ap_disconnected_t;

typedef struct luat_wlan_scan_result
{
    char ssid[33];
    char bssid[6];
    int16_t rssi;
    uint8_t ch;
}luat_wlan_scan_result_t;

typedef struct luat_wlan_station_info
{
    uint8_t ipv4_addr[4];
    uint8_t ipv4_netmask[4];
    uint8_t ipv4_gateway[4];
    uint8_t dhcp_enable;
}luat_wlan_station_info_t;


int luat_wlan_init(luat_wlan_config_t *conf);
int luat_wlan_mode(luat_wlan_config_t *conf);
int luat_wlan_ready(void);
int luat_wlan_connect(luat_wlan_conninfo_t* info);
int luat_wlan_disconnect(void);
int luat_wlan_scan(void);
int luat_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);

int luat_wlan_set_station_ip(luat_wlan_station_info_t *info);

// 配网相关
// --- smartconfig 配网
enum LUAT_WLAN_SC_TYPE {
    LUAT_SC_TYPE_STOP = 0,
    LUAT_SC_TYPE_ESPTOUCH,
    LUAT_SC_TYPE_AIRKISS,
    LUAT_SC_TYPE_ESPTOUCH_AIRKISS,
    LUAT_SC_TYPE_ESPTOUCH_V2
};

int luat_wlan_smartconfig_start(int tp);
int luat_wlan_smartconfig_stop(void);

// 数据类
int luat_wlan_get_mac(int id, char* mac);
int luat_wlan_set_mac(int id, const char* mac);
int luat_wlan_get_ip(int type, char* data);
const char* luat_wlan_get_hostname(int id);
int luat_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_wlan_set_ps(int mode);
int luat_wlan_get_ps(void);

int luat_wlan_get_ap_bssid(char* buff);
int luat_wlan_get_ap_rssi(void);
int luat_wlan_get_ap_gateway(char* buff);

// AP类
int luat_wlan_ap_start(luat_wlan_apinfo_t *apinfo);
int luat_wlan_ap_stop(void);



/**
 * @defgroup luat_wifiscan wifiscan扫描接口
 * @{
 */
#define Luat_MAX_CHANNEL_NUM     14
/// @brief wifiscan 扫描的优先级
typedef enum luat_wifiscan_set_priority
{
    LUAT_WIFISCAN_DATA_PERFERRD=0,/**< 数据优先*/
    LUAT_WIFISCAN_WIFI_PERFERRD
}luat_wifiscan_set_priority_t;

/// @brief wifiscan 控制参数结构体
typedef struct luat_wifiscan_set_info
{
    int   maxTimeOut;         //ms, 最大执行时间 取值范围4000~255000
    uint8_t   round;              //wifiscan total round 取值范围1~3
    uint8_t   maxBssidNum;        //wifiscan max report num 取值范围4~40
    uint8_t   scanTimeOut;        //s, max time of each round executed by RRC 取值范围1~255
    uint8_t   wifiPriority;       //CmiWifiScanPriority
    uint8_t   channelCount;       //channel count; if count is 1 and all channelId are 0, UE will scan all frequecny channel
    uint8_t   rsvd[3];
    uint16_t  channelRecLen;      //ms, max scantime of each channel
    uint8_t   channelId[Luat_MAX_CHANNEL_NUM];          //channel id 1-14: scan a specific channel
}luat_wifiscan_set_info_t;


#define LUAT_MAX_WIFI_BSSID_NUM      40 ///< bssid 的最大数量
#define LUAT_MAX_SSID_HEX_LENGTH     32 ///< SSID 的最大长度

/// @brief wifiscan 扫描结果
typedef struct luat_wifisacn_get_info
{
    uint8_t   bssidNum;                                   /**<wifi 个数*/
    uint8_t   rsvd;
    uint8_t   ssidHexLen[LUAT_MAX_WIFI_BSSID_NUM];        /**<SSID name 的长度*/
    uint8_t   ssidHex[LUAT_MAX_WIFI_BSSID_NUM][LUAT_MAX_SSID_HEX_LENGTH]; /**<SSID name*/
    int8_t    rssi[LUAT_MAX_WIFI_BSSID_NUM];           /**<rssi*/
    uint8_t   channel[LUAT_MAX_WIFI_BSSID_NUM];        /**<record channel index of bssid, 2412MHz ~ 2472MHz correspoding to 1 ~ 13*/ 
    uint8_t   bssid[LUAT_MAX_WIFI_BSSID_NUM][6];       /**<mac address is fixed to 6 digits*/ 
}luat_wifisacn_get_info_t;

/**
 * @brief 获取wifiscan 的信息
 * @param set_info[in] 设置控制wifiscan的参数
 * @param get_info[out] wifiscan 扫描结果 
 * @return int =0成功，其他失败
 */
int32_t luat_get_wifiscan_cell_info(luat_wifiscan_set_info_t * set_info,luat_wifisacn_get_info_t* get_info);

/**
 * @brief 获取wifiscan 的信息
 * @param set_info[in] 设置控制wifiscan的参数 
 * @return int =0成功，其他失败
 */
int luat_wlan_scan_nonblock(luat_wifiscan_set_info_t * set_info);

/**
 * @brief 设置wifiscan的参数
 * @param proi 扫描优先级，0低于数据传输 1高于数据传输
 * @param rounds 扫描轮数，至少1轮
 * @param one_round_timeout	1轮扫描的时间，单位秒，至少5秒
 * @param total_timeout	全局超时，单位秒
 * @return int =0成功，其他失败
 */
int luat_wlan_scan_set_param(uint8_t proi, uint8_t rounds, uint8_t one_round_timeout, uint8_t total_timeout);
/** @}*/
#endif
