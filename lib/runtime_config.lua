local M = {}

local cached

local function load_config()
    if cached ~= nil then
        return cached
    end

    local ok, cfg = pcall(require, "config")
    if ok and type(cfg) == "table" then
        cached = cfg
    else
        cached = {}
    end

    return cached
end

function M.get()
    local cfg = load_config()
    if cfg.enabled == true then
        return cfg
    end
    return {}
end

return M
