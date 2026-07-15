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
    return load_config()
end

function M.enabled()
    return load_config().enabled == true
end

function M.bootstrap_settings()
    local cfg = load_config()
    if cfg.enabled ~= true then
        return {}
    end

    local out = {}
    for _, key in ipairs({ "role", "central_url", "node_name", "sync_interval_sec", "node_liveness_sec" }) do
        local value = cfg[key]
        if value ~= nil then
            out[key] = tostring(value)
        end
    end
    return out
end

return M
