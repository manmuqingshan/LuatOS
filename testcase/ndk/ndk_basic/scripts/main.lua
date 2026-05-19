PROJECT = "ndk_lifecycle_test"
VERSION = "1.0.0"
AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local ndk_tests = require("ndk_test")

sys.taskInit(function()
    testrunner.runBatch("ndk_lifecycle_regression", {
        { testTable = ndk_tests, testcase = "ndk lifecycle regression" }
    })
end)

sys.run()
