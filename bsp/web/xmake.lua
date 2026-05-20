set_project("luac-web")
set_xmakever("3.0.4")

set_version("0.1.0", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local unpack = table.unpack or unpack
local luatos = "../../"
local pc = "../pc"

add_defines("__LUATOS__", "__XMAKE_BUILD__", "LUAT_USE_WEB=1", "__EMSCRIPTEN__")
add_cxflags("-sUSE_PTHREADS=1")
add_ldflags("-sUSE_PTHREADS=1", "-sPROXY_TO_PTHREAD=1", "-sALLOW_MEMORY_GROWTH=1")

set_optimize("fastest")
set_languages("gnu11", "cxx17")

add_includedirs("include", {public = true})
add_includedirs(pc.."/include", {public = true})
add_includedirs(luatos.."lua/include", {public = true})
add_includedirs(luatos.."luat/include", {public = true})
add_includedirs(pc.."/port/posix", {public = true})
add_includedirs(pc.."/port/rtos", {public = true})
add_includedirs(pc.."/port/uart", {public = true})
add_includedirs(pc.."/port/network", {public = true})

local function add_thirdparty_files(...)
    local options = is_host("windows") and {cflags = {"/W0"}, cxflags = {"/W0"}} or {cflags = {"-w"}, cxflags = {"-w"}}
    for _, pattern in ipairs({...}) do
        add_files(pattern, options)
    end
end

target("luatos-web")
    set_kind("binary")
    set_targetdir("$(builddir)/out")

    add_files("src/*.c")
    add_files("port/*.c")
    add_files("port/network/*.c")
    add_files("port/uart/*.c")

    -- PC reference sources reused by the browser BSP scaffold.
    add_files(
        pc.."/src/lua.c",
        pc.."/port/luat_base_mini.c",
        pc.."/port/luat_fs_mini.c",
        pc.."/port/luat_malloc_mini.c",
        pc.."/port/rtos/luat_msgbus_pc.c",
        pc.."/port/rtos/luat_rtos_mutex_pc.c",
        pc.."/port/rtos/luat_rtos_queue_pc.c",
        pc.."/port/rtos/luat_rtos_semaphore_pc.c",
        pc.."/port/rtos/luat_rtos_task_pc.c",
        pc.."/port/rtos/luat_timer_pc.c",
        pc.."/port/posix/luat_timer_engine.c"
    )

    add_thirdparty_files(luatos.."lua/src/*.c")

    -- Core runtime modules.
    add_includedirs(luatos.."components/printf", {public = true})
    add_files(luatos.."components/printf/*.c")

    add_files(
        luatos.."luat/modules/luat_base.c",
        luatos.."luat/modules/luat_lib_fs.c",
        luatos.."luat/modules/luat_lib_rtos.c",
        luatos.."luat/modules/luat_lib_timer.c",
        luatos.."luat/modules/luat_lib_log.c",
        luatos.."luat/modules/luat_lib_zbuff.c",
        luatos.."luat/modules/luat_lib_pack.c",
        luatos.."luat/modules/luat_lib_crypto.c",
        luatos.."luat/modules/luat_lib_mcu.c",
        luatos.."luat/modules/luat_lib_bit64.c",
        luatos.."luat/modules/luat_lib_uart.c",
        luatos.."luat/modules/luat_lib_mqttcore.c",
        luatos.."luat/modules/luat_lib_libcoap.c",
        luatos.."luat/modules/luat_lib_rtc.c",
        luatos.."luat/modules/luat_lib_gpio.c",
        luatos.."luat/modules/luat_lib_spi.c",
        luatos.."luat/modules/luat_lib_i2c.c",
        luatos.."luat/modules/luat_lib_i2s.c",
        luatos.."luat/modules/luat_lib_wdt.c",
        luatos.."luat/modules/luat_lib_pm.c",
        luatos.."luat/modules/luat_lib_adc.c",
        luatos.."luat/modules/luat_lib_pwm.c",
        luatos.."luat/modules/luat_irq.c",
        luatos.."luat/modules/luat_lib_can.c",
        luatos.."luat/modules/luat_lib_otp.c",
        luatos.."luat/modules/luat_main.c"
    )

    add_files(luatos.."luat/vfs/*.c")

    add_includedirs(luatos.."components/lfs", {public = true})
    add_files(luatos.."components/lfs/*.c")

    add_includedirs(luatos.."components/lua-cjson", {public = true})
    add_thirdparty_files(luatos.."components/lua-cjson/*.c")

    add_includedirs(luatos.."components/cjson", {public = true})
    add_thirdparty_files(luatos.."components/cjson/*.c")

    add_includedirs(luatos.."components/ndk/include", {public = true})
    add_files(luatos.."components/ndk/src/*.c")
    add_files(luatos.."components/ndk/binding/*.c")

    add_includedirs(luatos.."components/fft/inc", {public = true})
    add_files(luatos.."components/fft/src/*.c")
    add_files(luatos.."components/fft/binding/*.c")

    add_includedirs(luatos.."components/iotauth")
    add_files(luatos.."components/iotauth/*.c")

    add_files(luatos.."components/crypto/**.c")

    add_includedirs(luatos.."components/serialization/protobuf", {public = true})
    add_files(luatos.."components/serialization/protobuf/*.c")

    add_includedirs(luatos.."components/minmea")
    add_files(luatos.."components/minmea/*.c")

    add_includedirs(luatos.."components/gmssl/include")
    add_files(luatos.."components/gmssl/src/sm2_lib.c")
    add_files(luatos.."components/gmssl/bind/*.c")

    add_includedirs(luatos.."components/iconv")
    add_files(luatos.."components/iconv/*.c")

    add_includedirs(luatos.."components/miniz", {public = true})
    add_thirdparty_files(luatos.."components/miniz/*.c")

    add_includedirs(luatos.."components/fskv")
    add_files(luatos.."components/fskv/luat_lib_fskv.c")

    add_includedirs(luatos.."components/ymodem", {public = true})
    add_files(luatos.."components/ymodem/*.c")

    add_includedirs(luatos.."components/fastlz", {public = true})
    add_files(luatos.."components/fastlz/*.c")

    add_includedirs(luatos.."components/common", {public = true})
    add_files(luatos.."components/common/*.c")

    add_includedirs(luatos.."components/coremark", {public = true})
    add_files(luatos.."components/coremark/*.c")

    add_includedirs(luatos.."components/memprof/include", {public = true})
    add_files(luatos.."components/memprof/src/*.c")
    add_files(luatos.."components/memprof/binding/*.c")

    add_includedirs(luatos.."components/sqlite3/include", {public = true})
    add_files(luatos.."components/sqlite3/src/*.c")
    add_files(luatos.."components/sqlite3/binding/*.c")

    add_includedirs(luatos.."components/mobile")
    add_files(luatos.."components/mobile/*.c")

    add_includedirs(luatos.."components/sms/include", {public = true})
    add_files(luatos.."components/sms/**.c")

    add_includedirs(luatos.."components/network/adapter", {public = true})
    add_includedirs(luatos.."components/network/http_parser", {public = true})
    add_includedirs(luatos.."components/network/libhttp", {public = true})
    add_includedirs(luatos.."components/network/libemqtt", {public = true})
    add_includedirs(luatos.."components/network/libsntp", {public = true})
    add_includedirs(luatos.."components/network/errdump", {public = true})
    add_files(
        luatos.."components/network/adapter/*.c",
        luatos.."components/network/http_parser/*.c",
        luatos.."components/network/libhttp/*.c",
        luatos.."components/network/libemqtt/*.c",
        luatos.."components/network/libsntp/*.c",
        luatos.."components/network/errdump/*.c"
    )

target_end()
