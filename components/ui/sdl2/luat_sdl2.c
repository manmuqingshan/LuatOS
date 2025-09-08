#include "luat_base.h"
#include "luat_sdl2.h"

#include "SDL2/SDL.h"

#define LUAT_LOG_TAG "sdl2"
#include "luat_log.h"

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *framebuffer = NULL;

static uint32_t* fb;
static luat_sdl2_conf_t sdl_conf;

static void luat_sdl2_pump_events(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            // Graceful exit on window close
            exit(0);
        }
        // Other events are ignored; important is to pump to keep window responsive
    }
}

int luat_sdl2_init(luat_sdl2_conf_t *conf) {
    if (framebuffer != NULL) {
        LLOGD("SDL2 aready inited");
        return -1;
    }
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
        LLOGE("SDL_InitSubSystem failed: %s\n", SDL_GetError());
        return -1;
    }
    memcpy(&sdl_conf, conf, sizeof(luat_sdl2_conf_t));

    window = SDL_CreateWindow(conf->title == NULL ? "LuatOS" : conf->title,
                              SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                              conf->width, conf->height, 0);

    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    framebuffer = SDL_CreateTexture(renderer,
                                    SDL_PIXELFORMAT_ARGB8888,
                                    SDL_TEXTUREACCESS_STREAMING,
                                    conf->width,
                                    conf->height);
    // fb = luat_heap_malloc(sizeof(uint32_t) * conf->width * conf->height);
    luat_sdl2_pump_events();
    return 0;
}

int luat_sdl2_deinit(luat_sdl2_conf_t *conf) {
    SDL_DestroyTexture(framebuffer);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    // free(fb);
    framebuffer = NULL;
    renderer = NULL;
    window = NULL;
    // fb = NULL;
    return 0;
}

void luat_sdl2_draw(int16_t x1, int16_t y1, int16_t x2, int16_t y2, uint32_t* data) {
    SDL_Rect r;
    r.x = x1;
    r.y = y1;
    r.w = x2 - x1 + 1;
    r.h = y2 - y1 + 1;

    SDL_UpdateTexture(framebuffer, &r, data, r.w * 4);
}

void luat_sdl2_flush(void) {
    if (renderer && framebuffer)
    {
        SDL_RenderCopy(renderer, framebuffer, NULL, NULL);
        SDL_RenderPresent(renderer);
    }
    luat_sdl2_pump_events();
}
