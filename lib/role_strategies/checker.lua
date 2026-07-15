local db = require("lib.db")

local M = {}

function M.after_fetch(s, now, result)
  db.update_monitor_status(s.monitor_id, result.is_up, result.status_code, result.response_time_ms, result.new_failures)

  local _, err = http_post(s.central_url .. "/api/public/report/" .. s.monitor_id,
    json_encode({
      is_up = result.is_up,
      status_code = result.status_code,
      response_time_ms = result.response_time_ms,
      error_message = result.err_msg,
    }),
    {
      ["Content-Type"] = "application/json",
      ["X-Pulse-Checker-Token"] = s.central_token,
    })
  if err then
    log("Failed to report to central: " .. tostring(err))
  end
end

return M
