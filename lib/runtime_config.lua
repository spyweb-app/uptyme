local M = {}

local cached

local function load_config()
    if cached ~= nil then
        return cached
    end
    
    local ok, cfg = pcall(require, "config")
    if ok and type(cfg) == "table" then
        if cfg.central_url then
            cfg.central_url = cfg.central_url:gsub("/+$", "")
        end
        cached = cfg
    else
        cached = {}
    end
    
    return cached
end

function M.get()
    local cfg = load_config()
    if cfg.multi_node == true then
        return cfg
    end
    return {}
end

function M.logging()
    return load_config().logging or {}
end

function M.role()
    return M.get().role or "standalone"
end

function M.is_checker()
    return M.role() == "checker"
end

function M.is_central()
    return M.role() == "central"
end

function M.is_standalone()
    return M.role() == "standalone"
end

return M
