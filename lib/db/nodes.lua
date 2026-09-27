local M = {}

local NODE_COLS = "id, name, local_name, role, token_prefix, last_seen_at, active, stale_alert_minutes, stale_alerted_at, created_at, updated_at"
local NODE_AUTH_COLS = NODE_COLS .. ", token_hash"
local NODE_UPDATABLE = { "name", "stale_alert_minutes", "active" }

function M.get_node_by_prefix(prefix)
  return db_select_one("nodes", NODE_AUTH_COLS, "token_prefix", prefix)
end

function M.get_node(id)
  return db_select_one("nodes", NODE_COLS, "id", id)
end

function M.list_nodes()
  return db_query([[
    SELECT id, name, local_name, role, last_seen_at, active, stale_alert_minutes, stale_alerted_at, created_at, updated_at 
    FROM nodes WHERE role != 'central' ORDER BY created_at DESC
  ]])
end

function M.create_node(data)
  local ok, err = pcall(db_exec, [[
    INSERT INTO nodes (name, role, token_prefix, token_hash, active)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    data.name,
    data.role or "checker",
    data.token_prefix,
    data.token_hash,
    data.active == nil and 1 or (data.active ~= 0 and 1 or 0),
  })
  if not ok then return nil, err end
  return db_select_one("nodes", NODE_COLS, "token_prefix", data.token_prefix)
end

function M.update_node(id, data)
  local ok, err = db_update_by_id("nodes", id, data, NODE_UPDATABLE, { updated_at = true })
  if not ok then return nil, err end
  return M.get_node(id)
end

function M.get_node_reports(node_id, limit)
  limit = limit or 50
  return db_query([[
    SELECT r.monitor_id, r.is_up, r.status_code, r.response_time_ms, r.error_message, r.reported_at, m.name as monitor_name, m.url as monitor_url
    FROM node_reports r
    LEFT JOIN monitors m ON m.id = r.monitor_id
    WHERE r.node_id = ?
    ORDER BY r.reported_at DESC
    LIMIT ?
  ]], { node_id, limit })
end

function M.update_node_local_name(node_id, name)
  db_update_by_id("nodes", node_id, { local_name = name }, { "local_name" })
end

function M.touch_node(id)
  db_exec("UPDATE nodes SET last_seen_at = ?, stale_alerted_at = NULL, updated_at = ? WHERE id = ?", {
    os.time(),
    os.time(),
    id,
  })
end

function M.set_node_stale_alerted(id, ts)
  db_update_by_id("nodes", id, { stale_alerted_at = ts }, { "stale_alerted_at" })
end

function M.get_or_create_central_node()
  local rows = db_query("SELECT " .. NODE_COLS .. " FROM nodes WHERE role = 'central'")
  if #rows > 0 then return rows[1] end

  local ok = pcall(db_exec, [[
    INSERT INTO nodes (name, role, token_prefix, token_hash, active)
    VALUES (?, ?, ?, ?, ?)
  ]], { "central", "central", "__central__", "", 1 })
  if not ok then return nil end

  rows = db_query("SELECT " .. NODE_COLS .. " FROM nodes WHERE role = 'central'")
  return rows[1]
end

function M.get_nodes_with_reports(monitor_id, cutoff)
  return db_query([[
    SELECT n.id, r.is_up, r.reported_at
    FROM nodes n
    INNER JOIN node_reports r ON r.node_id = n.id AND r.monitor_id = ?
    WHERE n.active = 1
      AND r.reported_at >= ?
  ]], { monitor_id, cutoff })
end

function M.upsert_node_report(monitor_id, node_id, data)
  local now = os.time()
  local is_up = data.is_up ~= nil and (data.is_up ~= 0 and 1 or 0) or 1
  local vals = { monitor_id, node_id, is_up }
  table.insert(vals, data.status_code or -1)
  table.insert(vals, data.response_time_ms or -1)
  table.insert(vals, data.error_message or "")
  table.insert(vals, now)
  db_exec([[
    INSERT INTO node_reports (monitor_id, node_id, is_up, status_code, response_time_ms, error_message, reported_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(monitor_id, node_id) DO UPDATE SET
      is_up = excluded.is_up,
      status_code = excluded.status_code,
      response_time_ms = excluded.response_time_ms,
      error_message = excluded.error_message,
      reported_at = excluded.reported_at
  ]], vals)
end

function M.upsert_node_reports_batch(rows)
  if #rows == 0 then return end
  local now = os.time()
  local value_groups = {}
  local params = {}
  for _, row in ipairs(rows) do
    local is_up = row.is_up ~= nil and (row.is_up ~= 0 and 1 or 0) or 1
    table.insert(value_groups, "(?,?,?,?,?,?,?)")
    table.insert(params, row.monitor_id)
    table.insert(params, row.node_id)
    table.insert(params, is_up)
    table.insert(params, row.status_code or -1)
    table.insert(params, row.response_time_ms or -1)
    table.insert(params, row.error_message or "")
    table.insert(params, now)
  end
  db_exec([[
    INSERT INTO node_reports (monitor_id, node_id, is_up, status_code, response_time_ms, error_message, reported_at)
    VALUES ]] .. table.concat(value_groups, ",") .. [[
    ON CONFLICT(monitor_id, node_id) DO UPDATE SET
      is_up = excluded.is_up,
      status_code = excluded.status_code,
      response_time_ms = excluded.response_time_ms,
      error_message = excluded.error_message,
      reported_at = excluded.reported_at
  ]], params)
end

function M.reset_node_token(id, token_prefix, token_hash)
  db_update_by_id("nodes", id, { token_prefix = token_prefix, token_hash = token_hash },
    { "token_prefix", "token_hash" }, { updated_at = true })
  return M.get_node(id)
end

function M.delete_node(id)
  db_exec("DELETE FROM node_reports WHERE node_id = ?", { id })
  db_exec("DELETE FROM nodes WHERE id = ?", { id })
end

return M
