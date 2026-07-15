local check = require("lib.check")
local alert = require("alert")

local M = {}

function M.run(fetch_result, shared)
  local now = os.time()
  local response_time_ms = (fetch_result.response and fetch_result.response.time_ms) or 0

  local r = check.classify_status(fetch_result)
  local is_up, severity, status_code, err_msg = r.is_up, r.severity, r.status_code, r.err or ""

  if is_up == 1 and shared.check_value ~= "" then
    local cc = check.check_content(fetch_result.response and fetch_result.response.body, shared.check_value)
    if cc then
      is_up, severity, err_msg = 0, "DOWN", cc.err
    end
  end

  local new_failures = alert.compute_failures(is_up, severity, shared.prev_failures)

  return {
    is_up = is_up,
    severity = severity,
    status_code = status_code,
    err_msg = err_msg,
    new_failures = new_failures,
    response_time_ms = response_time_ms,
    now = now,
  }
end

return M
