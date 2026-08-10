local cluster_auth = require("lib.cluster_auth")
local runtime_config = require("lib.runtime_config")
local logger = require("lib.logger")

local M = {}

local function request(method, path, data)
    local cfg = runtime_config.get()
    if not runtime_config.is_checker() then return nil, "node is not a checker" end
    if not cfg.central_url or cfg.central_url == "" then return nil, "central_url not set" end
    if not cfg.auth_token or cfg.auth_token == "" then return nil, "auth_token not set" end

    local url = cfg.central_url .. "/api/public" .. path
    local headers = {
        [cluster_auth.HEADER_KEY] = cfg.auth_token,
        [cluster_auth.LOCAL_NAME] = cfg.node_name or "",
    }

    logger.debug("→ central " .. method .. " " .. path, "central.request")

    local resp, err
    if method == "GET" then
        resp, err = http_get(url, headers)
    else
        headers["Content-Type"] = "application/json"
        resp, err = http_post(url, json_encode(data), headers)
    end

    return resp, err
end

function M.get(path)
    return request("GET", path)
end

function M.post(path, data)
    return request("POST", path, data)
end

return M
