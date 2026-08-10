local normalize = require("lib.monitor_util").normalize
local runtime_config = require("lib.runtime_config")

local M = {}

-- Helpers shared by multiple functions in this module

local ALLOWED_SORTS = {
  name = "m.name",
  url = "m.url",
  response_time = "m.last_response_time_ms",
  created_at = "m.created_at",
  last_check_at = "m.last_check_at",
}

local function uptime_subqueries(now)
  return string.format([[
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) as up_24h,
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) as total_24h,
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) as up_7d,
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) as total_7d,
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) as up_30d,
    (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) as total_30d
  ]], now - 86400, now - 86400, now - 604800, now - 604800, now - 2592000, now - 2592000)
end

local function compute_uptime(m)
  m.uptime_24h = m.total_24h > 0 and math.floor((m.up_24h / m.total_24h) * 100) or nil
  m.uptime_7d = m.total_7d > 0 and math.floor((m.up_7d / m.total_7d) * 100) or nil
  m.uptime_30d = m.total_30d > 0 and math.floor((m.up_30d / m.total_30d) * 100) or nil
end

-- Query

function M.list_all()
  local now = os.time()
  local rows = db_query([[
    SELECT m.*,
  ]] .. uptime_subqueries(now) .. [[
    FROM monitors m
    ORDER BY m.created_at DESC
  ]])
  for _, m in ipairs(rows) do compute_uptime(m) end
  return rows
end

function M.monitor_list(opts)
  local page = opts.page or 1
  local per_page = opts.per_page or 25
  local sort = opts.sort or "created_at"
  local order = opts.order or "desc"
  local q = opts.q or ""
  local enabled = opts.enabled

  local sort_col = ALLOWED_SORTS[sort] or "m.created_at"
  local order_dir = order == "desc" and "DESC" or "ASC"

  local where_parts = {}
  local where_params = {}

  if q ~= "" then
    where_parts[#where_parts + 1] = "(m.name LIKE ? OR m.url LIKE ?)"
    where_params[#where_params + 1] = "%" .. q .. "%"
    where_params[#where_params + 1] = "%" .. q .. "%"
  end

  if enabled ~= nil then
    where_parts[#where_parts + 1] = "m.enabled = ?"
    where_params[#where_params + 1] = enabled
  end

  local where_clause = ""
  if #where_parts > 0 then
    where_clause = " WHERE " .. table.concat(where_parts, " AND ")
  end

  local count_row = db_query("SELECT COUNT(*) as cnt FROM monitors m" .. where_clause, where_params)
  local total = count_row[1].cnt

  local now = os.time()
  local all_params = {}
  for _, v in ipairs(where_params) do all_params[#all_params + 1] = v end

  local offset = (page - 1) * per_page
  all_params[#all_params + 1] = per_page
  all_params[#all_params + 1] = offset

  local rows = db_query([[
    SELECT m.*,
  ]] .. uptime_subqueries(now) .. [[
    FROM monitors m
  ]] .. where_clause .. " ORDER BY " .. sort_col .. " " .. order_dir .. " LIMIT ? OFFSET ?", all_params)

  for _, m in ipairs(rows) do compute_uptime(m) end

  local total_pages = math.ceil(total / per_page)
  if total_pages < 1 then total_pages = 1 end

  return {
    items = rows,
    total = total,
    page = page,
    per_page = per_page,
    total_pages = total_pages,
  }
end

function M.export_all()
  return db_query("SELECT * FROM monitors ORDER BY created_at DESC")
end

function M.export_syncable()
  return db_query([[
    SELECT id, name, url, method, interval_sec, timeout_ms, check_value,
           enabled, desktop_notify, check_cert, cert_threshold_days,
           created_at, updated_at
    FROM monitors
    ORDER BY created_at DESC
  ]])
end

function M.get(id)
  return db_first("SELECT * FROM monitors WHERE id = ?", { id })
end

function M.get_by_url(url)
  return db_first("SELECT * FROM monitors WHERE url = ?", { url })
end

function M.get_history(id, before, limit)
  return db_query([[
    SELECT id, monitor_id, status_code, response_time_ms, is_up, error_message, checked_at
    FROM check_history
    WHERE monitor_id = ? AND checked_at < ?
    ORDER BY checked_at DESC
    LIMIT ?
  ]], { id, before, limit })
end

function M.get_summary(id, days, group_unit)
  local since = os.time() - (days * 86400)

  if group_unit == "hour" then
    return db_query([[
      SELECT strftime('%Y-%m-%dT%H:00:00', checked_at, 'unixepoch') as period,
             COUNT(*) as total,
             SUM(is_up) as up_count
      FROM check_history
      WHERE monitor_id = ? AND checked_at >= ?
      GROUP BY period
      ORDER BY period DESC
    ]], { id, since })
  end

  if group_unit == "halfday" then
    return db_query([[
      SELECT strftime('%Y-%m-%dT', checked_at, 'unixepoch') ||
             CASE WHEN cast(strftime('%H', checked_at, 'unixepoch') as integer) < 12
                  THEN '00:00:00' ELSE '12:00:00' END as period,
             COUNT(*) as total,
             SUM(is_up) as up_count
      FROM check_history
      WHERE monitor_id = ? AND checked_at >= ?
      GROUP BY period
      ORDER BY period DESC
    ]], { id, since })
  end

  return db_query([[
    SELECT date(checked_at, 'unixepoch') as period,
           COUNT(*) as total,
           SUM(is_up) as up_count
    FROM check_history
    WHERE monitor_id = ? AND checked_at >= ?
    GROUP BY period
    ORDER BY period DESC
  ]], { id, since })
end

-- Write

function M.insert_monitor(entry)
  local n = normalize(entry)
  local ok, err = pcall(db_exec, [[
    INSERT OR IGNORE INTO monitors (name, url, method, interval_sec, timeout_ms, check_value, enabled, desktop_notify, check_cert, cert_threshold_days)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    entry.name,
    entry.url,
    n.method,
    n.interval_sec,
    n.timeout_ms,
    n.check_value,
    n.enabled,
    n.desktop_notify,
    n.check_cert,
    n.cert_threshold_days,
  })
  if ok then
    local row = db_query("SELECT id FROM monitors WHERE url = ?", { entry.url })
    if row[1] and runtime_config.is_central() then
      db_exec("INSERT OR IGNORE INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at) VALUES (?, 'UP', ?, ?)",
        { row[1].id, os.time(), os.time() })
    end
  end
  return ok, err
end

function M.update_monitor(id, sets, params)
  table.insert(sets, "updated_at = ?")
  table.insert(params, os.time())
  table.insert(params, id)
  db_exec("UPDATE monitors SET " .. table.concat(sets, ", ") .. " WHERE id = ?", params)
end

function M.delete_monitor(id)
  db_exec("DELETE FROM node_reports WHERE monitor_id = ?", { id })
  db_delete_by_id("monitors", id)
end

function M.sync_from_central(rows)
  rows = rows or {}
  local now = os.time()
  local seen = {}

  for _, entry in ipairs(rows) do
    local id = tonumber(entry.id)
    if id and entry.name and entry.url then
      seen[#seen + 1] = id
      local current = M.get(id)
      local n = normalize(entry)

      if current then
        db_exec([[
          UPDATE monitors
          SET name = ?, url = ?, method = ?, interval_sec = ?, timeout_ms = ?,
              check_value = ?, enabled = ?, desktop_notify = ?, check_cert = ?,
              cert_threshold_days = ?, updated_at = ?
          WHERE id = ?
        ]], {
          entry.name, entry.url, n.method, n.interval_sec, n.timeout_ms,
          n.check_value, n.enabled, n.desktop_notify, n.check_cert,
          n.cert_threshold_days, now, id
        })
      else
        db_exec([[
          INSERT INTO monitors (
              id, name, url, method, interval_sec, timeout_ms, check_value,
              enabled, desktop_notify, check_cert, cert_threshold_days,
              created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
          id, entry.name, entry.url, n.method, n.interval_sec, n.timeout_ms,
          n.check_value, n.enabled, n.desktop_notify, n.check_cert,
          n.cert_threshold_days, entry.created_at or now, entry.updated_at or now
        })
      end
    end
  end

  local disable_params = { now }
  local disable_clause = ""
  if #seen > 0 then
    local placeholders = {}
    for _, sid in ipairs(seen) do
      placeholders[#placeholders + 1] = "?"
      disable_params[#disable_params + 1] = sid
    end
    disable_clause = " AND id NOT IN (" .. table.concat(placeholders, ", ") .. ")"
  end

  db_exec("UPDATE monitors SET enabled = 0, updated_at = ? WHERE enabled = 1" .. disable_clause, disable_params)
end

-- Lifecycle (used by hooks)

function M.claim_next_due()
  local now = os.time()
  return db_query([[
    UPDATE monitors
    SET last_check_at = ?
    WHERE id = (
        SELECT id FROM monitors
        WHERE enabled = 1
          AND (last_check_at IS NULL OR (? - last_check_at) >= interval_sec)
        ORDER BY last_check_at ASC
        LIMIT 1
    )
    RETURNING id, name, url, method, timeout_ms, check_value, is_up, consecutive_failures,
              check_cert, cert_threshold_days, cert_last_check
  ]], { now, now })
end

function M.insert_check(monitor_id, status_code, response_time_ms, is_up, error_message)
  local now = os.time()
  db_exec("INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, error_message, checked_at) VALUES (?, ?, ?, ?, ?, ?)",
    { monitor_id, status_code, response_time_ms, is_up, error_message, now })
end

function M.insert_check_history_batch(rows)
  if #rows == 0 then return end
  local value_groups = {}
  local params = {}
  for _, row in ipairs(rows) do
    table.insert(value_groups, "(?,?,?,?,?,?)")
    table.insert(params, row.monitor_id)
    table.insert(params, row.status_code or -1)
    table.insert(params, row.response_time_ms or -1)
    table.insert(params, row.is_up ~= nil and (row.is_up ~= 0 and 1 or 0) or 1)
    table.insert(params, row.error_message or "")
    table.insert(params, row.checked_at or os.time())
  end
  db_exec("INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, error_message, checked_at) VALUES " .. table.concat(value_groups, ","), params)
end

function M.update_monitor_status(monitor_id, is_up, status_code, response_time_ms, consecutive_failures)
  local now = os.time()
  db_exec("UPDATE monitors SET is_up = ?, last_status_code = ?, last_response_time_ms = ?, consecutive_failures = ?, updated_at = ? WHERE id = ?",
    { is_up, status_code, response_time_ms, consecutive_failures, now, monitor_id })
end

-- Batch-update live status columns for many monitors. Only writes the 5 status
-- columns (never name/url/config) and only touches rows that still exist, so a
-- monitor deleted between buffer and flush cannot be resurrected. Chunked to
-- stay under SQLite's compound-SELECT term limit (the FROM row source is an
--... UNION ALL ...), which defaults to ~500.
function M.update_monitor_status_batch(rows)
  if #rows == 0 then return end
  local now = os.time()
  local CHUNK = 400
  for start = 1, #rows, CHUNK do
    local finish = math.min(start + CHUNK - 1, #rows)
    local value_parts = {}
    local params = {}
    for i = start, finish do
      local row = rows[i]
      table.insert(value_parts, "SELECT ? AS id, ? AS p_up, ? AS p_sc, ? AS p_rt, ? AS p_cf, ? AS p_ts")
      table.insert(params, row.monitor_id)
      table.insert(params, row.is_up ~= nil and (row.is_up ~= 0 and 1 or 0) or 1)
      table.insert(params, row.status_code or -1)
      table.insert(params, row.response_time_ms or -1)
      table.insert(params, row.consecutive_failures or 0)
      table.insert(params, now)
    end
    db_exec(
      "UPDATE monitors AS m SET is_up = v.p_up, last_status_code = v.p_sc, last_response_time_ms = v.p_rt, consecutive_failures = v.p_cf, updated_at = v.p_ts FROM (" ..
      table.concat(value_parts, " UNION ALL ") ..
      ") AS v WHERE m.id = v.id", params)
  end
end

function M.update_cert_info(monitor_id, not_after, days_left, checked_at)
  db_exec("UPDATE monitors SET cert_not_after = ?, cert_days_left = ?, cert_last_check = ?, updated_at = ? WHERE id = ?",
    { not_after, days_left, checked_at, os.time(), monitor_id })
end

-- Retention

function M.cleanup_old_history(days)
  days = days or M.get_int("retention_days", 90)
  local cutoff = os.time() - (days * 86400)
  local deleted = db_exec("DELETE FROM check_history WHERE checked_at < ?", { cutoff })
  return deleted
end

return M
