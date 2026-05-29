--[[
@module  nes_key_app
@summary NES按键配置提供者 — 接收 app 请求，返回按键绑定参数
@version 7.0
@date    2026.05.29

通信：
  APP 发 NES_APP_BIND → 引擎读 _G.NES_KEY_CONFIG（优先）
                        → 回退 project_config.nes_keys
                        → 发 NES_KEY_CFG(cfg)
]]

sys.subscribe("NES_APP_BIND", function()
    local cfg = _G.NES_KEY_CONFIG
    if not cfg or type(cfg) ~= "table" or #cfg == 0 then
        local pc = _G.project_config
        if pc and pc.nes_keys and type(pc.nes_keys) == "table" then
            cfg = pc.nes_keys
        end
    end
    if cfg and type(cfg) == "table" and #cfg > 0 then
        log.info("nes_key_app", "send NES_KEY_CFG", #cfg, "keys")
        sys.publish("NES_KEY_CFG", cfg)
    end
end)
