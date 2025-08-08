#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"

#ifdef LUAT_FREERTOS_FULL_INCLUDE
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#else
#include "FreeRTOS.h"
#include "queue.h"
#endif

static QueueHandle_t xQueue = {0};

void luat_msgbus_init(void) {
    if (!xQueue) {
        xQueue = xQueueCreate(256, sizeof(rtos_msg_t));
    }
}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    if (xQueue == NULL)
        return 1;
    #if 0
    if (luat_rtos_get_ipsr())
	{
        BaseType_t pxHigherPriorityTaskWoken;
		if (xQueueSendFromISR(xQueue, msg, &pxHigherPriorityTaskWoken) != pdPASS)
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
    }
    else
    {
        return xQueueSend(xQueue, msg, NULL) == pdTRUE ? 0 : 1;
    }
    #else
    return xQueueSendFromISR(xQueue, msg, NULL) == pdTRUE ? 0 : 1;
    #endif
}
uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    if (xQueue == NULL)
        return 1;
    return xQueueReceive(xQueue, msg, timeout) == pdTRUE ? 0 : 1;
}
uint32_t luat_msgbus_freesize(void) {
    return 1;
}

uint8_t luat_msgbus_is_empty(void) {
    return uxQueueMessagesWaiting(xQueue) == 0 ? 1 : 0;
}

uint8_t luat_msgbus_is_ready(void) {
	return xQueue?1:0;
}
