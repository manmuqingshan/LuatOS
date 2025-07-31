
#ifndef LUAT_GPIO_H
#define LUAT_GPIO_H


#include "luat_base.h"
#include "luat_gpio_legacy.h"

// 若bsp没有定义最大PIN编号, 那么默认给个128吧
#ifdef LUAT_USE_DRV_GPIO
#undef LUAT_GPIO_PIN_MAX
#define LUAT_GPIO_PIN_MAX 254
#else
#ifndef LUAT_GPIO_PIN_MAX
#define LUAT_GPIO_PIN_MAX   (127)
#endif
#endif

/**
 * @defgroup luatos_device_gpio GPIO接口
 * @{
 */

#define LUAT_GPIO_LOW                 (Luat_GPIO_LOW)  ///< GPIO配置为低电平
#define LUAT_GPIO_HIGH                (Luat_GPIO_HIGH) ///< GPIO配置为高电平

#define LUAT_GPIO_OUTPUT         (Luat_GPIO_OUTPUT) ///< GPIO配置为输出模式
#define LUAT_GPIO_INPUT          (Luat_GPIO_INPUT)  ///< GPIO配置为输入模式
#define LUAT_GPIO_IRQ            (Luat_GPIO_IRQ) ///< GPIO配置为中断模式

#define LUAT_GPIO_DEFAULT        (Luat_GPIO_DEFAULT) ///< GPIO配置为默认模式,EC618平台，上下拉只对输出模式有效，输入模式只有默认上下拉或者取消上下拉，普通的GPIO配置为LUAT_GPIO_DEFAULT，表示完全关闭上下拉；AGPIO软件上不支持配置上下拉，即使配置了也无效，一直是硬件开机或者复位时的默认状态
#define LUAT_GPIO_PULLUP         (Luat_GPIO_PULLUP) ///< GPIO配置为上拉模式
#define LUAT_GPIO_PULLDOWN       (Luat_GPIO_PULLDOWN)///< GPIO配置为下拉模式

#define LUAT_GPIO_RISING_IRQ             (Luat_GPIO_RISING) ///<上升沿中断
#define LUAT_GPIO_FALLING_IRQ            (Luat_GPIO_FALLING)///< 下降沿中断
#define LUAT_GPIO_BOTH_IRQ               (Luat_GPIO_BOTH) ///< 上升沿 下降沿都中断
#define LUAT_GPIO_HIGH_IRQ			(Luat_GPIO_HIGH_IRQ)	///< GPIO配置为高电平中断模式
#define LUAT_GPIO_LOW_IRQ			(Luat_GPIO_LOW_IRQ)	///< GPIO配置为低电平模式
#define LUAT_GPIO_NO_IRQ			(0xff) ///< GPIO没有中断模式

#define LUAT_GPIO_MAX_ID             (Luat_GPIO_MAX_ID) ///< 最大GPIO序号

//无效的GPIO,用作某些函数引脚不指定时使用
#define LUAT_GPIO_NONE                 (0xff)

/**
 * @brief GPIO控制参数
*/
typedef struct luat_gpio_cfg
{
    int pin; /**<引脚*/
    uint8_t mode;/**<GPIO模式*/
    uint8_t pull;/**<GPIO上下拉模式*/
    uint8_t irq_type;/**<GPIO中断模式*/
    uint8_t output_level;/**<GPIO输出高低电平选择*/
    luat_gpio_irq_cb irq_cb;/**<GPIO中断回调函数*/
    void* irq_args;/**<GPIO中断回调时用户参数*/
    uint8_t alt_fun;/**<有些SOC的GPIO会在不同引脚上被复用，通过alt_fun来确定具体用哪个,已废弃*/
} luat_gpio_cfg_t;


/**
 * @brief GPIO上下拉\中断设置参数
 */
typedef enum
{
	LUAT_GPIO_CMD_SET_PULL_MODE,/**<上下拉模式*/
	LUAT_GPIO_CMD_SET_IRQ_MODE,/**<中断模式*/
}LUAT_GPIO_CTRL_CMD_E;
/**
 * @brief GPIO设置默认参数
 * @param luat_gpio_cfg_t
*/
void luat_gpio_set_default_cfg(luat_gpio_cfg_t* gpio);
/**
 * @brief 打开GPIO
 * @param luat_gpio_cfg_t
*/
int luat_gpio_open(luat_gpio_cfg_t* gpio);
/**
 * @brief GPIO输出电平
 * @param Pin Pin序号
 * @param Level 1高电平，0低电平
 */
int luat_gpio_set(int pin, int level);

/**
 * @brief 读取GPIO输入电平
 * @param Pin Pin序号
 * @return 1高电平， 0低电平，其他无效
 */
int luat_gpio_get(int pin);
/**
 * @brief 关闭GPIO
 * @param Pin Pin序号
 */
void luat_gpio_close(int pin);
/**
 * @brief 设置GPIO中断回调函数
 * @param Pin Pin序号
 * @param cb  中断处理函数
 * @param args 中断函数参数
 * @return -1 失败 0 成功
 */
int luat_gpio_set_irq_cb(int pin, luat_gpio_irq_cb cb, void* args);

int luat_gpio_irq_enable(int pin, uint8_t enabled, uint8_t irq_type, void *arg);

/**
 * @brief GPIO模拟单线输出模式
 * @param Pin Pin序号
 * @param Data 输出电平序列
 * @param BitLen 输出电平序列中一共有几个bit
 * @param Delay 每个bit之间的delay
 * @return 无
 * @attention 在同一个GPIO输出一组脉冲, 注意, len的单位是bit, 高位在前.
 */

void luat_gpio_pulse(int pin, uint8_t *level, uint16_t len, uint16_t delay_ns);
/**
 * @brief GPIO上下拉\中断单独设置函数
 * @param pin Pin序号
 * @param LUAT_GPIO_CTRL_CMD_E 设置命令 LUAT_GPIO_CMD_SET_PULL_MODE 设置上下拉命令 LUAT_GPIO_CMD_SET_IRQ_MODE
 * @param param 设置参数 参数取自上下拉、以及中断的宏定义
 * @return -1 失败 0 成功
 */
int luat_gpio_ctrl(int pin, LUAT_GPIO_CTRL_CMD_E cmd, int param);
void luat_gpio_iomux(int pin, int new_pad, uint8_t alt);
/**
 * @brief gpio方式输出bit0和bit1给WS2812B，不输出reset，由于严格的时序要求，会关闭中断来保证时序，因此驱动大量LED灯时会对其他驱动，甚至整个系统有影响。建议用多个GPIO分组驱动大量LED灯，1个GPIO最好不要超过32个灯
 * @param pin GPIO号
 * @param data 输出的byte数据，驱动不对数据做任何RGB顺序调整，请自行调整
 * @param len 输出的byte数量，必须是3的倍数
 * @param frame_cnt 在一次关闭全局中断到开启全局中断中间发送的帧数，1帧3个byte。分段发送是为了能让其他中断有响应的时间，但是造成提前发送reset而导致剩下的灯不亮。写0则一次性全部发送
 * @param bit0h bit0的高电平额外延迟，默认写10，如果高电平时间不足酌情增加
 * @param bit0l bit0的低电平额外延迟，默认写0
 * @param bit1h bit1的高电平额外延迟，默认写10，如果高电平时间不足酌情增加
 * @param bit1l bit1的低电平额外延迟，默认写0
 * @return -1 失败 0 成功
 */
int luat_gpio_driver_ws2812b(int pin, uint8_t *data, uint32_t len, uint32_t frame_cnt, uint8_t bit0h, uint8_t bit0l, uint8_t bit1h, uint8_t bit1l);

/**
 * @brief gpio方式驱动yhm27xx,short mode操作1个寄存器读写
 * @param pin GPIO号
 * @param chip_id yhm27xx device address
 * @param reg yhm27xx 寄存器地址
 * @param is_read 1 读 0写
 * @param data 读取时传出数据，写入时传入数据
 * @return 0 成功，其他失败
 */
int luat_gpio_driver_yhm27xx(uint32_t pin, uint8_t chip_id, uint8_t reg, uint8_t is_read, uint8_t *data);
/** @}*/

void luat_gpio_mode(int pin, int mode, int pull, int initOutput);

void luat_gpo_open(uint8_t id);
void luat_gpo_output(uint8_t pin, uint8_t level);
uint8_t luat_gpo_get_output_level(uint8_t id);
#endif
