/*
这个文件是用来实现蓝牙的, 需要代理全部参数给airlink

1. 要把全部函数都实现, 如果不支持的就返回错误
2. 一律打包luat_drv_ble_msg_t

数据传输的数据结构如下:
uint16_t cmd_id; // 蓝牙cmd的id
uint16_t version; // 主机协议版本号, 目前都是0
uint32_t reserved; // 保留字段, 目前都是0
// 然后是命令自身的数据
*/
#include "luat_base.h"
#include "luat_drv_ble.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"

#define LUAT_LOG_TAG "drv.ble"
#include "luat_log.h"

luat_ble_cb_t g_drv_ble_cb;

int luat_ble_init(void* args, luat_ble_cb_t luat_ble_cb) {
    LLOGD("执行luat_ble_init %p", luat_ble_cb);
    g_drv_ble_cb = luat_ble_cb;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, 8 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_INIT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_deinit(void* args) {
    LLOGD("执行luat_ble_deinit");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, 8 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_DEINIT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_name(void* args, char* name, uint8_t len) {
    LLOGD("执行luat_ble_set_name");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + sizeof(luat_drv_ble_msg_t) + len + 1
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_SET_NAME;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    // 然后是名字长度, 1字节
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &len, 1);
    // 然后是名字
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 1, name, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_max_mtu(void* args, uint16_t max_mtu) {
    LLOGE("set max mtu %d not support yet", max_mtu);
    return -1;
}

// advertise
int luat_ble_create_advertising(void* args, luat_ble_adv_cfg_t* adv_cfg) {
    LLOGD("执行luat_ble_create_advertising");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + sizeof(luat_ble_adv_cfg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_CREATE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    // 然后是结构体大小
    uint16_t sizeof_adv = sizeof(luat_ble_adv_cfg_t);
    memcpy(cmd->data + 8 + 8, &sizeof_adv, 2);
    // 然后是数据
    memcpy(cmd->data + 8 + 8 + 2, adv_cfg, sizeof_adv);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_adv_data(void* args, uint8_t* adv_buff, uint8_t adv_len) {
    LLOGD("执行luat_ble_set_adv_data %p %d", adv_buff, adv_len);
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + adv_len
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_SET_DATA;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    // 然后是结构体大小
    uint16_t datalen = adv_len;
    memcpy(cmd->data + 8 + 8, &datalen, 2);
    // 然后是名字
    memcpy(cmd->data + 8 + 8 + 2, adv_buff, datalen);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_scan_rsp_data(void* args, uint8_t* rsp_data, uint8_t rsp_len) {
    LLOGD("执行luat_ble_set_scan_rsp_data %p %d", rsp_data, rsp_len);
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + rsp_len
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_SET_SCAN_RSP_DATA;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    // 然后是结构体大小
    uint16_t datalen = rsp_len;
    memcpy(cmd->data + 8 + 8, &datalen, 2);
    // 然后是名字
    memcpy(cmd->data + 8 + 8 + 2, rsp_data, datalen);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_start_advertising(void* args) {
    LLOGD("执行luat_ble_start_advertising");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_START;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_stop_advertising(void* args) {
    LLOGD("执行luat_ble_start_advertising");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_STOP;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_delete_advertising(void* args) {
    LLOGD("执行luat_ble_start_advertising");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_ADV_DELETE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


// gatt
int luat_ble_create_gatt(void* args, luat_ble_gatt_service_t* gatt) {
    LLOGD("执行luat_ble_create_gatt");
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_gatt_service_t) 
               + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t)
               + 16
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_GATT_CREATE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    
    // 数据部分
    // 首先是luat_ble_gatt_service_t结构的大小
    tmp = sizeof(luat_ble_gatt_service_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    // 然后是luat_ble_gatt_chara_t的大小
    tmp = sizeof(luat_ble_gatt_chara_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 2, &tmp, 2);
    // 然后是服务id的数量
    tmp = gatt->characteristics_num;
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 2 + 2, &tmp, 2);

    // 头部拷贝完成, 拷贝数据
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 8, gatt, sizeof(luat_ble_gatt_service_t));
    // 然后是服务id
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 8 + sizeof(luat_ble_gatt_service_t), 
        gatt->characteristics, gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t));

    item.cmd = cmd;

    // LLOGD("gatt 数据长度 %d %d %d", item.len, cmd->len, cmd->len - sizeof(luat_drv_ble_msg_t));
    // luat_airlink_print_buff("bt req HEX", cmd->data, cmd->len);
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// slaver
int luat_ble_read_response_value(void* args, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint32_t len) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_write_notify_value(void* args, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint16_t len) {
    LLOGE("not support yet");
    return -1;
}


// scanning
int luat_ble_create_scanning(void* args, luat_ble_scan_cfg_t* scan_cfg) {
    LLOGD("执行luat_ble_create_scanning");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + sizeof(luat_ble_scan_cfg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_SCAN_CREATE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    // 然后是结构体大小
    uint16_t sizeof_scan = sizeof(luat_ble_scan_cfg_t);
    memcpy(cmd->data + 8 + 8, &sizeof_scan, 2);
    // 然后是数据
    memcpy(cmd->data + 8 + 8 + 2, scan_cfg, sizeof_scan);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_start_scanning(void* args) {
    LLOGD("执行luat_ble_start_scanning");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_SCAN_START;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_stop_scanning(void* args) {
    LLOGD("执行luat_ble_stop_scanning");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_SCAN_STOP;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_delete_scanning(void* args) {
    LLOGD("执行luat_ble_delete_scanning");
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_SCAN_DELETE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_connect(void* args, uint8_t* adv_addr,uint8_t adv_addr_type) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_disconnect(void* args, uint8_t conn_idx) {
    LLOGE("not support yet");
    return -1;
}
