local sha256 = require("lib.sha256")

local M = {}

function M.get_node_by_prefix(prefix)
  local rows = db_query("SELECT * FROM nodes WHERE token_prefix = ?", { prefix })
  return rows[1]
end

function M.get_node(id)
  local rows = db_query("SELECT * FROM nodes WHERE id = ?", { id })
  return rows[1]
end

function M.list_nodes()
  return db_query("SELECT * FROM nodes ORDER BY created_at DESC")
end

function M.create_node(data)
  local token = data.token or ""
  local prefix, secret = token:match("^([^%.]+)%.(.+)$")
  if not prefix or not secret then
    return nil, "invalid token format"
  end

  local ok, err = pcall(db_exec, [[
    INSERT INTO nodes (name, role, token_prefix, token_hash, active)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    data.name,
    data.role or "checker",
    prefix,
    sha256.hex(secret),
    data.active == nil and 1 or (data.active ~= 0 and 1 or 0),
  })
  if not ok then return nil, err end
  return M.get_node_by_prefix(prefix)
end

function M.touch_node(id)
  db_exec("UPDATE nodes SET last_seen_at = ?, updated_at = ? WHERE id = ?", {
    os.time(),
    os.time(),
    id,
  })
end

function M.get_or_create_central_node()
  local rows = db_query("SELECT * FROM nodes WHERE role = 'central'")
  if #rows > 0 then return rows[1] end

  local ok = pcall(db_exec, [[
    INSERT INTO nodes (name, role, token_prefix, token_hash, active)
    VALUES (?, ?, ?, ?, ?)
  ]], { "central", "central", "__central__", "", 1 })
  if not ok then return nil end

  rows = db_query("SELECT * FROM nodes WHERE role = 'central'")
  return rows[1]
end

function M.get_nodes_with_reports(monitor_id)
  return db_query([[
    SELECT n.id, n.last_seen_at, COALESCE(r.is_up, 1) as is_up
    FROM nodes n
    LEFT JOIN node_reports r ON r.node_id = n.id AND r.monitor_id = ?
    WHERE n.active = 1
  ]], { monitor_id })
end

function M.upsert_node_report(monitor_id, node_id, data)
  local now = os.time()
  db_exec([[
    INSERT INTO node_reports (monitor_id, node_id, is_up, status_code, response_time_ms, error_message, reported_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(monitor_id, node_id) DO UPDATE SET
      is_up = excluded.is_up,
      status_code = excluded.status_code,
      response_time_ms = excluded.response_time_ms,
      error_message = excluded.error_message,
      reported_at = excluded.reported_at
  ]], {
    monitor_id,
    node_id,
    data.is_up ~= nil and (data.is_up ~= 0 and 1 or 0) or 1,
    data.status_code,
    data.response_time_ms,
    data.error_message or "",
    now,
  })
end

return M
