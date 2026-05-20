#include "luat_ndk.h"
#include "luat_ndk_abi.h"
#include "luat_ndk_host.h"

#include <string.h>

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

static inline luat_ndk_event_header_t* luat_ndk_event_header_ptr(luat_ndk_t *ctx) {
    if (!ctx || !ctx->ram) return NULL;
    size_t offset = ctx->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET;
    if (offset + LUAT_NDK_EVENT_HDR_SIZE > ctx->ram_size) return NULL;
    return (luat_ndk_event_header_t*)(ctx->ram + offset);
}

static inline luat_ndk_event_t* luat_ndk_event_slot_ptr(luat_ndk_t *ctx, uint16_t slot_index) {
    if (!ctx || !ctx->ram) return NULL;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header_ptr(ctx);
    if (!hdr || slot_index >= hdr->slot_count) return NULL;
    size_t offset = ctx->exchange_offset + LUAT_NDK_EVENT_HDR_OFFSET + LUAT_NDK_EVENT_HDR_SIZE + (slot_index * sizeof(luat_ndk_event_t));
    if (offset + sizeof(luat_ndk_event_t) > ctx->ram_size) return NULL;
    return (luat_ndk_event_t*)(ctx->ram + offset);
}

void luat_ndk_event_reset(luat_ndk_t *ctx) {
    if (!ctx) return;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header_ptr(ctx);
    if (!hdr) return;
    hdr->host_write = 0;
    hdr->guest_read = 0;
    hdr->overflow = 0;
    // slot_count is already set during init, do not reset
}

void luat_ndk_event_set_last_error(luat_ndk_t *ctx, luat_ndk_host_err_t err) {
    if (!ctx) return;
    ctx->last_error = (uint32_t)err;
}

void luat_ndk_event_push_timer(luat_ndk_t *ctx, uint32_t delay_us) {
    if (!ctx) return;
    luat_ndk_event_header_t *hdr = luat_ndk_event_header_ptr(ctx);
    if (!hdr) return;
    
    // Check if ring is full
    uint16_t next_write = (hdr->host_write + 1) % hdr->slot_count;
    if (next_write == (hdr->guest_read % hdr->slot_count)) {
        // Ring is full, set overflow and drop event
        hdr->overflow = 1;
        return;
    }
    
    // Write event to current host_write position
    uint16_t slot = hdr->host_write % hdr->slot_count;
    luat_ndk_event_t *event = luat_ndk_event_slot_ptr(ctx, slot);
    if (!event) return;
    
    event->type = LUAT_NDK_EVENT_TIMER;
    event->source = 0;
    event->data = delay_us;
    
    // Advance host_write
    hdr->host_write = next_write;
}
