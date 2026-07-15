local db = require("lib.db")
local alert = require("alert")

local M = {}

function M.check_and_alert(s, now)
  if s.check_cert ~= 1 then return nil end

  local last = s.cert_last_check
  if last and (now - tonumber(last)) < 86400 then return nil end

  local host = s.monitor_url:match("https://([^/]+)")
  if not host then return nil end

  local cert, err = tls_probe(host)
  if cert then
    db.update_cert_info(s.monitor_id, cert.not_after, cert.days_left, now)
    if cert.days_left < s.cert_threshold_days then
      alert.do_alert(s, "DOWN", "Certificate expires in " .. cert.days_left .. " days (" .. cert.subject .. ")")
    end
    return { checked = true, ok = true, days_left = cert.days_left, subject = cert.subject }
  else
    db.update_cert_info(s.monitor_id, nil, nil, now)
    alert.do_alert(s, "DOWN", "TLS probe failed: " .. (err or "unknown"))
    return { checked = true, ok = false, err = err }
  end
end

return M
