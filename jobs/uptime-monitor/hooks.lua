local db = require("lib.db")
local pipeline = require("lib.check_pipeline")
local alert = require("alert")

local settings = db.get_settings()
local role = settings.role or "standalone"
local strategy = require("lib.role_strategies." .. role)

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
        cert_threshold_days = m.cert_threshold_days or 14,
        cert_last_check = m.cert_last_check,
    }

    if role == "central" then
        ctx.shared.central_node = db.get_or_create_central_node()
        if ctx.shared.central_node then
            db.touch_node(ctx.shared.central_node.id)
        end
    elseif role == "checker" then
        ctx.shared.central_url = settings.central_url
        ctx.shared.central_token = settings.central_token
        ctx.shared.node_name = settings.node_name or os.hostname and os.hostname() or "checker"
    end

    return request
end

function after_fetch(fetch_result, ctx)
    local s = ctx.shared
    if not s.monitor_id then return nil end

    local result = pipeline.run(fetch_result, s)
    strategy.after_fetch(s, result.now, result)

    -- Cert check — standalone and central only, skip on checker
    if s.check_cert == 1 and role ~= "checker" then
        local last = s.cert_last_check
        if not last or (result.now - tonumber(last)) >= 86400 then
            local host = s.monitor_url:match("https://([^/]+)")
            if host then
                local cert, err = tls_probe(host)
                if cert then
                    db.update_cert_info(s.monitor_id, cert.not_after, cert.days_left, result.now)
                    if cert.days_left < s.cert_threshold_days then
                        alert.do_alert(s, "DOWN", "Certificate expires in " .. cert.days_left .. " days (" .. cert.subject .. ")")
                    end
                else
                    db.update_cert_info(s.monitor_id, nil, nil, result.now)
                    alert.do_alert(s, "DOWN", "TLS probe failed: " .. (err or "unknown"))
                end
            end
        end
    end

    return nil
end
