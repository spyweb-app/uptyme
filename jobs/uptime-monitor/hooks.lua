local db = require("lib.db")
local pipeline = require("lib.check_pipeline")
local runtime_config = require("lib.runtime_config")

local cfg = runtime_config.get()
local role = runtime_config.role()
local role_strategies = require("lib.role_strategies")

db.ensure_schema()

function before_fetch(request, ctx)
    local rows = db.claim_next_due()
    if #rows == 0 then return nil end

    local m = rows[1]
    request.url = m.url
    request.method = (m.check_value and m.check_value ~= "") and "GET" or (m.method or "HEAD")

    ctx.shared = {
        monitor_id = m.id,
        monitor_name = m.name,
        monitor_url = m.url,
        check_value = m.check_value or "",
        was_up = m.is_up == 1,
        prev_failures = m.consecutive_failures or 0,
        desktop_notify = m.desktop_notify or 0,
        check_cert = m.check_cert or 0,
        cert_threshold_days = m.cert_threshold_days or 0,
        cert_last_check = m.cert_last_check,
    }

    if role == "central" then
        ctx.shared.central_node = db.get_or_create_central_node()
        if ctx.shared.central_node then
            db.touch_node(ctx.shared.central_node.id)
        end
    elseif role == "checker" then
        ctx.shared.central_url = cfg.central_url or ""
        ctx.shared.central_token = cfg.auth_token or ""
        ctx.shared.node_name = cfg.node_name or "checker"
    end

    return request
end

function after_fetch(fetch_result, ctx)
    local s = ctx.shared
    if not s.monitor_id then return nil end

    local result = pipeline.run(fetch_result, s)
    role_strategies.after_fetch(role, s, result.now, result)
    return nil
end
