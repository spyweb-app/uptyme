local db = require("lib.db")
local runtime_config = require("lib.runtime_config")

db.ensure_schema()

function before_fetch(request, ctx)
    local s = db.get_settings()
    if s.role ~= "checker" then
        return nil
    end

    local cfg = runtime_config.get()
    if cfg.enabled ~= true then
        return nil
    end

    local central_url = s.central_url or cfg.central_url or ""
    local auth_token = cfg.auth_token or ""
    if central_url == "" or auth_token == "" then
        return nil
    end

    local headers = { ["X-Pulse-Checker-Token"] = auth_token }
    local version_res, err = http_get(central_url .. "/api/public/cluster_version", headers)
    if not version_res then
        log("cluster-sync: version fetch failed: " .. tostring(err))
        return nil
    end

    local remote_v = tonumber(version_res.body) or 0
    local local_v = tonumber(global_store_get("cluster_monitors_version") or "0") or 0
    if remote_v == local_v then
        return nil
    end

    local export_res, export_err = http_get(central_url .. "/api/public/cluster_export", headers)
    if not export_res then
        log("cluster-sync: export fetch failed: " .. tostring(export_err))
        return nil
    end

    local rows = json_decode(export_res.body)
    if type(rows) ~= "table" then
        log("cluster-sync: invalid export payload")
        return nil
    end

    db.sync_from_central(rows)
    global_store_set("cluster_monitors_version", tostring(remote_v))
    return nil
end
