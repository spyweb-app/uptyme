local db = require("lib.db")
local alert = require("alert")
local check_buffer = require("lib.check_buffer")
local report_buffer = require("lib.report_buffer")

local M = {}

local function err_text(err)
  if type(err) == "table" then
    return tostring(err.message or err.error or "unknown error")
  end
  return tostring(err or "unknown error")
end

local function cert_threshold(s)
  local own = tonumber(s.cert_threshold_days) or 0
  if own >= 1 then return own end
  return db.get_int("cert_threshold_days", 14)
end

local function cert_check(s, now)
  if s.check_cert ~= 1 then return nil end
  local last = s.cert_last_check
  if last and (now - tonumber(last)) < 86400 then return nil end
  local host = s.monitor_url:match("https://([^/]+)")
  if not host then return nil end
  local cert, err = tls_probe(host)
  if cert then
    db.update_cert_info(s.monitor_id, cert.not_after, cert.days_left, now)
    if cert.days_left < cert_threshold(s) then
      alert.do_alert(s, "DOWN", "Certificate expires in " .. cert.days_left .. " days (" .. cert.subject .. ")")
    end
  else
    db.update_cert_info(s.monitor_id, nil, nil, now)
    alert.do_alert(s, "DOWN", "TLS probe failed: " .. err_text(err))
  end
end

function M.after_fetch(role, s, now, result)
  check_buffer.push_status({
    monitor_id = s.monitor_id,
    is_up = result.is_up,
    status_code = result.status_code,
    response_time_ms = result.response_time_ms,
    consecutive_failures = result.new_failures,
  })

  if role == "checker" then
    report_buffer.push({
      monitor_id = s.monitor_id,
      is_up = result.is_up,
      status_code = result.status_code,
      response_time_ms = result.response_time_ms,
      error_message = result.err_msg,
    })
    return
  end

  check_buffer.push_history({
    monitor_id = s.monitor_id,
    status_code = result.status_code,
    response_time_ms = result.response_time_ms,
    is_up = result.is_up,
    error_message = result.err_msg,
    checked_at = now,
  })
  cert_check(s, now)

  if role == "standalone" then
    alert.maybe_alert(s, result.severity, result.new_failures, now, result.status_code, result.err_msg)
  elseif role == "central" then
    check_buffer.push_node_report({
      monitor_id = s.monitor_id,
      node_id = s.central_node.id,
      is_up = result.is_up,
      status_code = result.status_code,
      response_time_ms = result.response_time_ms,
      error_message = result.err_msg,
    })
  end
end

return M
