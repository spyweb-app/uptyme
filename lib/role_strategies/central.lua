local db = require("lib.db")
local consensus = require("lib.consensus")
local cert_checker = require("lib.cert_checker")

local M = {}

function M.after_fetch(s, now, result)
  db.insert_check(s.monitor_id, result.status_code, result.response_time_ms, result.is_up, result.err_msg)
  db.update_monitor_status(s.monitor_id, result.is_up, result.status_code, result.response_time_ms, result.new_failures)
  db.upsert_node_report(s.monitor_id, s.central_node.id, {
    is_up = result.is_up,
    status_code = result.status_code,
    response_time_ms = result.response_time_ms,
    error_message = result.err_msg,
  })
  consensus.evaluate(s.monitor_id, result.is_up)
  cert_checker.check_and_alert(s, now)
end

return M
