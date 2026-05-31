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

function lf_suite.test_little_flash_utest_init_stats()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_init_stats") == true, "lf.utest(ftl_init_stats) 应为 true")
end

function lf_suite.test_little_flash_utest_oob_read_error_scan()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_oob_read_error_scan") == true, "lf.utest(ftl_oob_read_error_scan) 应为 true")
end

function lf_suite.test_little_flash_utest_wait_ready_timeout()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_wait_ready_timeout") == true, "lf.utest(ftl_wait_ready_timeout) 应为 true")
end

function lf_suite.test_little_flash_utest_recover_crc_invalid()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_recover_crc_invalid") == true, "lf.utest(ftl_recover_crc_invalid) 应为 true")
end

function lf_suite.test_little_flash_utest_recover_journal_out_of_range()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_recover_journal_out_of_range") == true, "lf.utest(ftl_recover_journal_out_of_range) 应为 true")
end

function lf_suite.test_little_flash_utest_repeat_mark_bad_idempotent()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_repeat_mark_bad_idempotent") == true, "lf.utest(ftl_repeat_mark_bad_idempotent) 应为 true")
end

t.lf_suite = lf_suite
return t
