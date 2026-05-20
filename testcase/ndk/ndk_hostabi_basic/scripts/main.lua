-- main.lua
-- NDK host ABI basic test entry point

PROJECT = "ndk_hostabi_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local ndk_hostabi_tests = require("ndk_hostabi_test")

sys.taskInit(function()
    testrunner.runBatch("ndk_hostabi", {
        { testTable = ndk_hostabi_tests, testcase = "ndk host abi regression" }
    })
end)

sys.run()
