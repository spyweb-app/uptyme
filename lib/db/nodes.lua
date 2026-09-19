local M = {}

function M.get_node_by_prefix(prefix)
  return db_first("SELECT * FROM nodes WHERE token_prefix = ?", { prefix })
end

function M.get_node(id)
  return db_first("SELECT * FROM nodes WHERE id = ?", { id })
end

function M.list_nodes()
  return db_query("SELECT id, name, local_name, role, last_seen_at, active, created_at, updated_at FROM nodes WHERE role != 'central' ORDER BY created_at DESC")
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
  return M.get_node_by_prefix(data.token_prefix)
end

function M.update_node(id, data)
  local sets, params = db_build_set_clause(data, { "name" })
  if #sets == 0 then return nil, "no fields to update" end
  table.insert(params, os.time())
  table.insert(params, id)
  db_exec("UPDATE nodes SET " .. table.concat(sets, ", ") .. ", updated_at = ? WHERE id = ?",
    { table.unpack(params) })
  return M.get_node(id)
end

function M.deactivate_node(id)
  db_exec("UPDATE nodes SET active = 0, updated_at = ? WHERE id = ?", { os.time(), id })
  return M.get_node(id)
end

function M.activate_node(id)
  db_exec("UPDATE nodes SET active = 1, updated_at = ? WHERE id = ?", { os.time(), id })
  return M.get_node(id)
end

function M.get_node_reports(node_id, limit)
  limit = limit or 50
  return db_query([[
    SELECT r.monitor_id, r.is_up, r.status_code, r.response_time_ms, r.error_message, r.reported_at,
           m.name as monitor_name, m.url as monitor_url
    FROM node_reports r
    LEFT JOIN monitors m ON m.id = r.monitor_id
    WHERE r.node_id = ?
    ORDER BY r.reported_at DESC
    LIMIT ?
  ]], { node_id, limit })
end

function M.update_node_local_name(node_id, name)
  db_exec("UPDATE nodes SET local_name = ? WHERE id = ?", { name, node_id })
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
  db_exec("UPDATE nodes SET token_prefix = ?, token_hash = ?, updated_at = ? WHERE id = ?",
    { token_prefix, token_hash, os.time(), id })
  return M.get_node(id)
end

function M.delete_node(id)
  db_exec("DELETE FROM node_reports WHERE node_id = ?", { id })
  db_exec("DELETE FROM nodes WHERE id = ?", { id })
end

return M
