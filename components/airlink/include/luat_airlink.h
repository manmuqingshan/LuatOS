#ifndef LUAT_AIRLINK_H
#define LUAT_AIRLINK_H

typedef struct luat_airlink_cmd
{
    uint16_t cmd; // 命令, 从0x0001开始, 到0xfffe结束
    uint16_t len; // 数据长度,最高64k, 实际使用最高2k
    uint64_t cmd_id; // 命令id, 起始1, 不需要ACK的指令, 可以传0, 逐个递增
    uint32_t revert; // 预留4字节的空余区域
    uint8_t data[0];
}luat_airlink_cmd_t;

int luat_airlink_start(int id);

int luat_airlink_stop(int id);

void luat_airlink_data_pack(uint8_t* buff, size_t len, uint8_t* dst);
void luat_airlink_data_unpack(uint8_t* buff, size_t len, size_t* pkg_offset, size_t* pkg_size);

void luat_airlink_task_start(void);
void luat_airlink_print_buff(const char* tag, uint8_t* buff, size_t len);
void luat_airlink_on_data_recv(uint8_t *data, size_t len);

typedef int (*luat_airlink_cmd_exec)(luat_airlink_cmd_t* cmd, void* userdata);

typedef struct luat_airlink_cmd_reg
{
    uint16_t id;
    luat_airlink_cmd_exec exec;
}luat_airlink_cmd_reg_t;


#endif
