local i2cId = 0
local da267Addr = 0x26
local intPin = 39
local function ind()
    if gpio.get(intPin) == 1 then
        log.info("da267", "interrupt")
        i2c.send(i2cId, da267Addr, 0x02, 1)
        local data = i2c.recv(i2cId, da267Addr, 6)
        if data and #data == 6 then
            local xl, xm, yl, ym, zl, zm = string.unpack(">bbbbbb", data)
            local x, y, z = (xm << 8 | xl >> 4), (ym << 8 | yl >> 4), (zm << 8 | zl >> 4)
            log.info("da267", "x:", x, "y:", y, "z:", z)
        else
            sys.publish("RESTORE_GSENSOR")
        end
    end
end
gpio.setup(intPin, ind)

local function init()
    i2c.close(i2cId)
    i2c.setup(i2cId, i2c.SLOW)
    i2c.send(i2cId, da267Addr, {0x00, 0x24}, 1)
    i2c.send(i2cId, da267Addr, {0x0F, 0x00}, 1)
    sys.wait(20)
    i2c.send(i2cId, da267Addr, {0x11, 0x34}, 1)
    i2c.send(i2cId, da267Addr, {0x10, 0x06}, 1)
    sys.wait(50)

    -- reduce power consumption
    i2c.send(i2cId, da267Addr, {0x8C, 0x00}, 1)

    -- init active interrupt
    i2c.send(i2cId, da267Addr, {0x16, 0x87}, 1)
    i2c.send(i2cId, da267Addr, {0x34, 0x00}, 1)
    i2c.send(i2cId, da267Addr, {0x38, 0x05}, 1)
    i2c.send(i2cId, da267Addr, {0x39, 0x05}, 1)
    i2c.send(i2cId, da267Addr, {0x3A, 0x05}, 1)
    i2c.send(i2cId, da267Addr, {0x19, 0x04}, 1)

    -- init step counter
    i2c.send(i2cId, da267Addr, {0x33, 0x80}, 1)
end

sys.taskInit(function()
    while true do
        init()
        while true do
            local result = sys.waitUntil("RESTORE_GSENSOR", 60 * 1000)
            if result then
                break
            end
            i2c.send(i2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(i2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                break
            end
        end
    end
end)