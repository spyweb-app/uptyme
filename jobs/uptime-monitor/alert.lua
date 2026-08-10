local db = require("lib.db")
local notifier = require("lib.notifier")

local M = {}

function M.compute_failures(is_up, severity, prev_failures)
    if is_up == 0 then
        return prev_failures + 1
    elseif severity == "BLOCKED" then
        return prev_failures
    end
    return 0
end

function M.do_alert(s, severity, message)
    store_set("alerted:" .. s.monitor_id, tostring(os.time()))
    notifier.dispatch(s.monitor_id, {
        monitor = s.monitor_name,
        url = s.monitor_url,
        severity = severity,
        message = message,
        timestamp = os.time(),
    })
    if s.desktop_notify == 1 then
        notify(severity .. ": " .. s.monitor_name, message .. "\n" .. s.monitor_url, 8000)
    end
end

function M.maybe_alert(s, severity, new_failures, now, status_code, err_msg)
    if severity == "DOWN" then
        if s.was_up then
            M.do_alert(s, severity, "Status changed from UP to DOWN: " .. err_msg)
        elseif new_failures >= 3 then
            local cooldown = db.get_int("alert_cooldown_sec", 300)
            local last_alert = store_get("alerted:" .. s.monitor_id)
            if not last_alert or (now - tonumber(last_alert)) >= cooldown then
                M.do_alert(s, severity, "Consecutive failures: " .. new_failures .. " - " .. err_msg)
            end
        end
    elseif severity == "BLOCKED" and s.was_up then
        M.do_alert(s, severity, "HTTP " .. status_code .. " - Access denied by server")
    elseif severity == "UP" and not s.was_up then
        M.do_alert(s, "UP", "Monitor recovered - HTTP " .. status_code)
    end
end

return M
