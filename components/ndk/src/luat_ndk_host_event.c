#include "luat_ndk.h"
#include "luat_ndk_abi.h"
#include "luat_ndk_host.h"

#include <string.h>

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

luat_ndk_event_header_t* luat_ndk_event_header(luat_ndk_t *ctx) {
    if (!ctx || !ctx->ram) return NULL;
    if (ctx->exchange_size < (LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE)) return NULL;
    return (luat_ndk_event_header_t*)(ctx->ram + ctx->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET);
}

static inline luat_ndk_event_t* luat_ndk_event_slot_ptr(luat_ndk_t *ctx, uint32_t slot_index) {
    if (!ctx || !ctx->ram) return NULL;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header(ctx);
    if (!hdr || slot_index >= hdr->slot_count) return NULL;
    size_t event_offset = LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE + (slot_index * sizeof(luat_ndk_event_t));
    if (event_offset + sizeof(luat_ndk_event_t) > ctx->exchange_size) return NULL;
    return (luat_ndk_event_t*)(ctx->ram + ctx->exchange_offset + event_offset);
}

void luat_ndk_event_push(luat_ndk_t *ctx, uint16_t type, uint16_t source, uint32_t data) {
    if (!ctx) return;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header(ctx);
    if (!hdr || hdr->slot_count == 0) return;

    uint32_t next_write = (hdr->host_write + 1) % hdr->slot_count;
    if (next_write == (hdr->guest_read % hdr->slot_count)) {
        hdr->overflow = 1;
        return;
    }

    uint32_t slot = hdr->host_write % hdr->slot_count;
    luat_ndk_event_t *event = luat_ndk_event_slot_ptr(ctx, slot);
    if (!event) return;

    event->type = type;
    event->source = source;
    event->data = data;
    hdr->host_write = next_write;
}

void luat_ndk_event_reset(luat_ndk_t *ctx) {
    if (!ctx) return;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header(ctx);
    if (!hdr) return;
    hdr->host_write = 0;
    hdr->guest_read = 0;
    hdr->slot_count = ctx->event_slots;
    hdr->overflow = 0;
}

void luat_ndk_event_set_last_error(luat_ndk_t *ctx, luat_ndk_host_err_t err) {
    if (!ctx) return;
    ctx->last_error = (uint32_t)err;
}

void luat_ndk_event_push_timer(luat_ndk_t *ctx, uint32_t delay_us) {
    luat_ndk_event_push(ctx, LUAT_NDK_EVENT_TIMER, 0, delay_us);
}
