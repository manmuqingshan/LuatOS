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
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_drv_ble.h"

#define LUAT_LOG_TAG "drv.ble"
#include "luat_log.h"

luat_ble_cb_t g_drv_ble_cb;

#undef LLOGD
#define LLOGD(...)

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
    LLOGD("执行luat_ble_create_gatt %d", gatt->characteristics_num);
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    int ret = 0;

    uint16_t descriptor_totalNum = 0;
    for (size_t i = 0; i < gatt->characteristics_num; i++) {
        descriptor_totalNum += gatt->characteristics[i].descriptors_num;
        // LLOGD("统计GATT描述符数量 %d/%d", gatt->characteristics[i].descriptors_num, descriptor_totalNum);
    }

    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_gatt_service_t) 
               + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t)
               + descriptor_totalNum * sizeof(luat_ble_gatt_descriptor_t)
               + 16
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        ret = -101;
        goto cleanup;
    }
    
    // 数据部分
    uint8_t ptr[1024] = {0};

    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_GATT_CREATE;
    memcpy(ptr, &msg, sizeof(luat_drv_ble_msg_t));
    
    // LLOGD("ptr %p cmd %p cmd->data %p", ptr, cmd + 1, cmd->data);
    #if 1
    luat_ble_gatt_pack(gatt, ptr + sizeof(luat_drv_ble_msg_t), NULL);
    // luat_airlink_hexdump("GATT_A1", cmd->data, cmd->len);
    #else
    tmp = sizeof(luat_ble_gatt_service_t);
    memcpy(ptr + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    // 然后是luat_ble_gatt_chara_t的大小
    tmp = sizeof(luat_ble_gatt_chara_t);
    memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 2, &tmp, 2);
    // 然后是服务id的数量
    tmp = gatt->characteristics_num;
    memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 2 + 2, &tmp, 2);
    // 然后是luat_ble_gatt_descriptor_t的大小
    tmp = sizeof(luat_ble_gatt_descriptor_t);
    memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 2 + 2 + 2, &tmp, 2);

    // 头部拷贝完成, 拷贝数据
    memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 8, gatt, sizeof(luat_ble_gatt_service_t));
    // 然后是服务id
    memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 8 + sizeof(luat_ble_gatt_service_t), 
        gatt->characteristics, gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t));
    
    for (size_t i = 0; i < gatt->characteristics_num; i++)
    {
        uint8_t descriptor_num = gatt->characteristics[i].descriptors_num;
        // 然后是描述符id
        memcpy(ptr + sizeof(luat_drv_ble_msg_t) + 8 + sizeof(luat_ble_gatt_service_t) + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t) + i * sizeof(luat_ble_gatt_descriptor_t), 
        gatt->characteristics[i].descriptor, descriptor_num * sizeof(luat_ble_gatt_descriptor_t));
    }
    #endif
    memcpy(cmd->data, ptr, cmd->len);
    // LLOGD("----> %s %s", __DATE__, __TIME__);

    // luat_airlink_hexdump("GATT_A2", cmd->data, cmd->len);

    item.cmd = cmd;

    // LLOGD("gatt 数据长度 %d %d %d", item.len, cmd->len, cmd->len - sizeof(luat_drv_ble_msg_t));
    // luat_airlink_print_buff("bt req HEX", cmd->data, cmd->len);
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);

cleanup:
    for (size_t i = 0; i < gatt->characteristics_num; i++)
    {
        if (gatt->characteristics[i].descriptor) {
            luat_heap_free(gatt->characteristics[i].descriptor);
            gatt->characteristics[i].descriptor = NULL;
        }
    }
    luat_heap_free(gatt->characteristics);
    gatt->characteristics = NULL;
    return ret;
}

int luat_ble_write_notify_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t len) {
    LLOGD("执行luat_ble_write_notify_value");
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + len + sizeof(uint16_t)
               + 16
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_WRITE_NOTIFY;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = len
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    if (uuid_descriptor) {
        memcpy(&req.descriptor, uuid_descriptor, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), data, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_write_indicate_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t len) {
    LLOGD("执行luat_ble_write_indicate_value");
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + len + sizeof(uint16_t)
               + 16
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_WRITE_INDICATION;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = len
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    if (uuid_descriptor) {
        memcpy(&req.descriptor, uuid_descriptor, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), data, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_write_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t *data, uint16_t len) {
    LLOGD("执行luat_ble_write_value");
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + len + sizeof(uint16_t)
               + 16
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_WRITE_VALUE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = len
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    if (uuid_descriptor) {
        memcpy(&req.descriptor, uuid_descriptor, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), data, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
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


int luat_ble_connect(void* args, luat_ble_connect_req_t *conn) {
    LLOGD("执行luat_ble_connect");
    if (luat_airlink_sversion() < 11) {
        LLOGE("ble:connect not support, ble version is %d", luat_airlink_sversion());
        return -1;
    }
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(luat_ble_connect_req_t) + 2
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    uint16_t tmp = sizeof(luat_ble_connect_req_t);
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_CONNECT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    // 然后是结构体大小
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    // 然后是连接请求数据
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t) + 2, conn, sizeof(luat_ble_connect_req_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return -1;
}

int luat_ble_disconnect(void* args) {
    LLOGD("执行luat_ble_disconnect");
    if (luat_airlink_sversion() < 11) {
        LLOGE("ble:disconnect not support, ble version is %d", luat_airlink_sversion());
        return -1;
    }
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + sizeof(luat_drv_ble_msg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_DISCONNECT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_read_value(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, luat_ble_uuid_t* uuid_descriptor, uint8_t **data, uint16_t* len) {
    LLOGD("执行luat_ble_read_value");
    if (luat_airlink_sversion() < 11) {
        LLOGE("ble:read_value not support, ble version is %d", luat_airlink_sversion());
        return -1;
    }
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + sizeof(uint16_t)
               + 16
    };
    // 暂时全是0
    *data = NULL;
    *len = 0;

    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_READ_VALUE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = len
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    if (uuid_descriptor) {
        memcpy(&req.descriptor, uuid_descriptor, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    // memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), data, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    LLOGI("luat_ble_read_value 执行完成");
    return 0;
}

int luat_ble_notify_enable(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, uint8_t enable) {
    LLOGD("执行luat_ble_notify_enable %d", enable);
    if (luat_airlink_sversion() < 11) {
        LLOGE("ble:notify_enable not support, ble version is %d", luat_airlink_sversion());
        return -1;
    }
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + sizeof(uint16_t)
               + 16
    };

    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_NOTIFY_ENABLE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = 1
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), &enable, 1);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_indicate_enable(luat_ble_uuid_t* uuid_service, luat_ble_uuid_t* uuid_characteristic, uint8_t enable) {
    LLOGD("执行luat_ble_indicate_enable %d", enable);
    if (luat_airlink_sversion() < 15) {
        LLOGE("ble:indicate_enable not support, ble version is %d", luat_airlink_sversion());
        return -1;
    }
    uint16_t tmp = 0;
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) 
               + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t) 
               + sizeof(uint16_t)
               + 16
    };

    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    
    luat_drv_ble_msg_t msg = { .id = seq};
    msg.cmd_id = LUAT_DRV_BT_CMD_BLE_INDICATE_ENABLE;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));
    luat_ble_rw_req_t req = {
        .len = 1
    };
    if (uuid_service) {
        memcpy(&req.service, uuid_service, sizeof(luat_ble_uuid_t));
    }
    if (uuid_characteristic) {
        memcpy(&req.characteristic, uuid_characteristic, sizeof(luat_ble_uuid_t));
    }
    tmp = sizeof(luat_ble_rw_req_t);
    memcpy(cmd->data + sizeof(luat_drv_ble_msg_t), &tmp, 2);
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t), &req, sizeof(luat_ble_rw_req_t));
    memcpy(cmd->data + 2 + sizeof(luat_drv_ble_msg_t) + sizeof(luat_ble_rw_req_t), &enable, 1);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}
