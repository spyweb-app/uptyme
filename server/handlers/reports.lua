local H = require("helpers")
local cluster_auth = require("lib.cluster_auth")
local consensus = require("lib.consensus")
local db = require("lib.db")

local M = {}

function M.report(self)
  local node = cluster_auth.verify(self)
  if not node then return H.json_response(401, nil, "Unauthorized") end

  local monitor_id = tonumber(self.path_args[1])
  local data = json_decode(self.body or "")
  if not monitor_id or not data or data.is_up == nil then
    return H.json_response(400, nil, "Invalid report payload — monitor_id and is_up required")
  end

  local monitor = db.get(monitor_id)
  if not monitor then
    return H.json_response(404, nil, "Monitor not found")
  end

  db.upsert_node_report(monitor_id, node.id, {
    is_up = data.is_up,
    status_code = data.status_code,
    response_time_ms = data.response_time_ms,
    error_message = data.error_message,
  })

  local result = consensus.evaluate(monitor_id, data.is_up)

  return H.json_response(200, {
    ok = true,
    transition = result.transition,
    status = result.status,
    skipped = result.skipped,
  })
end

return M
