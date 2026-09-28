local db = require("lib.db")
local central = require("lib.central_client")
local runtime_config = require("lib.runtime_config")
local notifier = require("lib.notifier")
local logger = require("lib.logger")

local function bootstrap()
    if not runtime_config.is_checker() then return end
    db.ensure_schema()

    local cfg = runtime_config.get()
    if not cfg.central_url or cfg.central_url == "" then
        logger.error("central_url not set — checker cannot reach central", "startup.config")
    end
    if not cfg.auth_token or cfg.auth_token == "" then
        logger.error("auth_token not set — checker cannot authenticate", "startup.config")
    end

    local s = db.get_settings()
    if s.cluster_node_id then return end

    local resp = central.get("/node_me")
    if not resp then return end

    local data = json_decode(resp.body)
    if not data or not data.success or not data.data then return end

    db.update_settings({
        cluster_node_id = tostring(data.data.id),
        cluster_node_name = data.data.name,
    })
    logger.info("bootstrapped as node: " .. data.data.name .. " (id=" .. data.data.id .. ")", "startup")
end

bootstrap()

local conn_state = { failures = 0, was_down = false }

local function contact_success()
    conn_state.failures = 0
    if conn_state.was_down then
        conn_state.was_down = false
        return { event = "up" }
    end
    return nil
end

local function contact_failure(err)
    conn_state.failures = conn_state.failures + 1
    local threshold = runtime_config.get().central_alert_failures or 3
    if conn_state.failures >= threshold and not conn_state.was_down then
        conn_state.was_down = true
        return { event = "down", err = err }
    end
    return nil
end

local function emit_connectivity(event)
    if not event then return end
    local cfg = runtime_config.get()
    local ca = cfg.checker_alerts or {}
    local severity = event.event == "down" and "DOWN" or "UP"
    local message = severity == "DOWN"
        and "Central unreachable — " .. (cfg.central_url or "unknown") .. " (after " .. (cfg.central_alert_failures or 3) .. " consecutive failures)"
            .. (event.err and (": " .. logger.err_msg(event.err)) or "")
        or "Central connection restored — " .. (cfg.central_url or "unknown")

    if event.event == "down" then
        logger.error(message, "sync.connectivity")
    elseif event.event == "up" then
        logger.info(message, "sync.connectivity")
    end

    if ca.desktop ~= false then
        notify(severity .. ": Central", message, 8000)
    end
    if ca.channels and #ca.channels > 0 then
        notifier.dispatch_config(ca.channels, {
            monitor = "Central", severity = severity,
            url = cfg.central_url or "", message = message, timestamp = os.time(),
        })
    end
end

local cached_version = 0

function before_fetch()
    if not runtime_config.is_checker() then return nil end
    local version_res, err = central.get("/cluster_version")

    local event
    if version_res then
        event = contact_success()
    else
        event = contact_failure(err)
        if conn_state.failures == 1 then
            logger.warn("central unreachable, first failure — " .. logger.err_msg(err), "sync.connectivity")
        end
    end
    emit_connectivity(event)

    if not version_res then return nil end

    local remote_v = tonumber(version_res.body) or 0
    if remote_v == cached_version then
        return nil
    end

    local export_res, export_err = central.get("/cluster_export")
    if not export_res then
        logger.error("export fetch failed: " .. logger.err_msg(export_err), "sync.export")
        return nil
    end

    local rows = json_decode(export_res.body)
    if type(rows) ~= "table" then
        logger.warn("invalid export payload", "sync.export")
        return nil
    end

    db.sync_from_central(rows)
    cached_version = remote_v
    return nil
end
