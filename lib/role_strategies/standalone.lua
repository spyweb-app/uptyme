local db = require("lib.db")
local alert = require("alert")
local cert_checker = require("lib.cert_checker")

local M = {}

function M.after_fetch(s, now, result)
  db.insert_check(s.monitor_id, result.status_code, result.response_time_ms, result.is_up, result.err_msg)
  db.update_monitor_status(s.monitor_id, result.is_up, result.status_code, result.response_time_ms, result.new_failures)
  alert.maybe_alert(s, result.severity, result.new_failures, now, result.status_code, result.err_msg)
  cert_checker.check_and_alert(s, now)
end

return M
