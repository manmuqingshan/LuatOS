#ifndef LUAT_DRV_BLE_H
#define LUAT_DRV_BLE_H

typedef struct luat_drv_ble_msg
{
    uint64_t id; // 命令seq序号
    uint16_t cmd_id;
    uint16_t len;
    uint16_t version;
    uint16_t reserved;
    uint8_t data[0];
}luat_drv_ble_msg_t;

// 定义蓝牙cmd id

enum {
    LUAT_DRV_BT_CMD_BT_INIT = 0,
    LUAT_DRV_BT_CMD_BT_DEINIT,
    LUAT_DRV_BT_CMD_BLE_INIT,
    LUAT_DRV_BT_CMD_BLE_DEINIT,
    LUAT_DRV_BT_CMD_BLE_GATT_CREATE, // 创建GATT
    LUAT_DRV_BT_CMD_BLE_SET_NAME, // 设置设备名
    LUAT_DRV_BT_CMD_BLE_ADV_CREATE, // 创建广播
    LUAT_DRV_BT_CMD_BLE_ADV_START, // 开始广播
    LUAT_DRV_BT_CMD_BLE_ADV_STOP, // 停止广播
    LUAT_DRV_BT_CMD_BLE_ADV_DELETE, // 删除广播
    LUAT_DRV_BT_CMD_BLE_ADV_SET_DATA, // 设置广播数据
    LUAT_DRV_BT_CMD_BLE_ADV_SET_SCAN_RSP_DATA, // 设置广播响应数据
    LUAT_DRV_BT_CMD_BLE_SCAN_CREATE, // 创建扫描
    LUAT_DRV_BT_CMD_BLE_SCAN_START, // 开始扫描
    LUAT_DRV_BT_CMD_BLE_SCAN_STOP,  // 停止扫描
    LUAT_DRV_BT_CMD_BLE_SCAN_DELETE, // 删除扫描

    LUAT_DRV_BT_CMD_BLE_EVENT_CB = 128, // 事件回调

    LUAT_DRV_BT_CMD_MAX
};

int luat_drv_bt_task_start(void);
int luat_drv_bt_msg_send(luat_drv_ble_msg_t *msg);

#endif
