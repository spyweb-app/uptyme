local M = {}

local history_buffer = {}
local node_report_buffer = {}
local status_buffer = {}

function M.push_history(row)
  table.insert(history_buffer, {
    monitor_id = row.monitor_id,
    status_code = row.status_code,
    response_time_ms = row.response_time_ms,
    is_up = row.is_up,
    error_message = row.error_message,
    checked_at = row.checked_at,
  })
end

function M.push_node_report(row)
  table.insert(node_report_buffer, row)
end

function M.push_status(row)
  table.insert(status_buffer, {
    monitor_id = row.monitor_id,
    is_up = row.is_up,
    status_code = row.status_code,
    response_time_ms = row.response_time_ms,
    consecutive_failures = row.consecutive_failures,
  })
end

function M.drain_history()
  local rows = history_buffer
  history_buffer = {}
  return rows
end

function M.drain_node_reports()
  local rows = node_report_buffer
  node_report_buffer = {}
  return rows
end

function M.drain_status()
  local rows = status_buffer
  status_buffer = {}
  return rows
end

function M.any_pending()
  return #history_buffer > 0 or #node_report_buffer > 0 or #status_buffer > 0
end

function M.total_rows()
  return #history_buffer + #node_report_buffer + #status_buffer
end

return M