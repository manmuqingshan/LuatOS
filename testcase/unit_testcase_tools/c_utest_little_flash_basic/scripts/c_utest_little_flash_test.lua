local t = {}

local lf_suite = {}

function lf_suite.test_little_flash_utest_identity_map()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_identity_map") == true, "lf.utest(ftl_identity_map) 应为 true")
end

function lf_suite.test_little_flash_utest_badblock_remap()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_badblock_remap") == true, "lf.utest(ftl_badblock_remap) 应为 true")
end

function lf_suite.test_little_flash_utest_powerfail_recovery()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_powerfail_recovery") == true, "lf.utest(ftl_powerfail_recovery) 应为 true")
end

function lf_suite.test_little_flash_utest_gc_trigger()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_gc_trigger") == true, "lf.utest(ftl_gc_trigger) 应为 true")
end

t.lf_suite = lf_suite
return t
