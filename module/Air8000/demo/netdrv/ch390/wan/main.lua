-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")


-- pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 所有GPIO高电平输出3.3V

-- require "lan"
require "wan"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

