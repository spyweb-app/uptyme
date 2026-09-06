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

function M.get_summary(monitor_ids, days, group_unit)
  local since = os.time() - (days * 86400)
  local ids = type(monitor_ids) == "table" and monitor_ids or { monitor_ids }
  local bulk = #ids > 1

  local placeholders = {}
  for _ = 1, #ids do placeholders[#placeholders + 1] = "?" end
  local where = "monitor_id IN (" .. table.concat(placeholders, ",") .. ")"

  local period_expr
  if group_unit == "hour" then
    period_expr = "strftime('%Y-%m-%dT%H:00:00', checked_at, 'unixepoch')"
  elseif group_unit == "halfday" then
    period_expr = [[strftime('%Y-%m-%dT', checked_at, 'unixepoch') ||
      CASE WHEN cast(strftime('%H', checked_at, 'unixepoch') as integer) < 12
           THEN '00:00:00' ELSE '12:00:00' END]]
  else
    period_expr = "date(checked_at, 'unixepoch')"
  end

  local monitor_col = bulk and "monitor_id, " or ""
  local group_by = bulk and ("monitor_id, " .. period_expr) or period_expr
  local order_by = bulk and ("monitor_id, " .. period_expr .. " DESC") or (period_expr .. " DESC")

  local params = {}
  for _, id in ipairs(ids) do params[#params + 1] = id end
  params[#params + 1] = since

  return db_query(string.format([[
    SELECT %s%s as period,
           COUNT(*) as total,
           SUM(is_up) as up_count,
           SUM(CASE WHEN is_up = 0 THEN 1 ELSE 0 END) as down_checks,
           SUM(CASE WHEN is_up = 1 AND status_code >= 400
                    AND status_code < 500 THEN 1 ELSE 0 END) as blocked_checks,
           AVG(CASE WHEN response_time_ms > 0 THEN response_time_ms END) as avg_response_ms
    FROM check_history
    WHERE %s AND checked_at >= ?
    GROUP BY %s
    ORDER BY %s
  ]], monitor_col, period_expr, where, group_by, order_by), params)
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
  db_exec("DELETE FROM status_page_monitors WHERE monitor_id = ?", { id })
  db_exec("DELETE FROM status_pages WHERE monitor_id = ?", { id })
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

-- Global dashboard stats

local function global_series(days)
  local since = os.time() - (days * 86400)
  local rows = db_query([[
    SELECT date(checked_at, 'unixepoch') as period,
           COUNT(*) as total,
           SUM(is_up) as up_count
    FROM check_history
    WHERE checked_at >= ?
    GROUP BY period
    ORDER BY period ASC
  ]], { since })
  local out = {}
  for _, r in ipairs(rows) do
    local total = tonumber(r.total) or 0
    local up = tonumber(r.up_count) or 0
    out[#out + 1] = {
      period = r.period,
      total = total,
      up_count = up,
      uptime = total > 0 and math.floor((up / total) * 100) or 0,
    }
  end
  return out
end

local function global_aggregates(now)
  local monitor = db_first([[
    SELECT COUNT(*) as total,
           SUM(CASE WHEN enabled = 1 THEN 1 ELSE 0 END) as enabled,
           SUM(CASE WHEN enabled = 0 THEN 1 ELSE 0 END) as disabled,
           SUM(CASE WHEN enabled = 1 AND is_up = 1 THEN 1 ELSE 0 END) as up,
           SUM(CASE WHEN enabled = 1 AND is_up = 0 THEN 1 ELSE 0 END) as down,
           SUM(CASE WHEN enabled = 1 AND is_up IS NULL THEN 1 ELSE 0 END) as unknown
    FROM monitors
  ]])

  local history = db_first([[
    SELECT
      SUM(CASE WHEN checked_at >= ? AND is_up = 1 THEN 1 ELSE 0 END) as up_24h,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_24h,
      SUM(CASE WHEN checked_at >= ? AND is_up = 1 THEN 1 ELSE 0 END) as up_7d,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_7d,
      SUM(CASE WHEN checked_at >= ? AND is_up = 1 THEN 1 ELSE 0 END) as up_30d,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_30d
    FROM check_history
  ]], {
    now - 86400, now - 86400,
    now - 604800, now - 604800,
    now - 2592000, now - 2592000,
  })

  local function uptime(up, total)
    up = tonumber(up) or 0
    total = tonumber(total) or 0
    return total > 0 and math.floor((up / total) * 10000) / 100 or nil
  end

  return {
    total = tonumber(monitor.total) or 0,
    enabled = tonumber(monitor.enabled) or 0,
    disabled = tonumber(monitor.disabled) or 0,
    up = tonumber(monitor.up) or 0,
    down = tonumber(monitor.down) or 0,
    unknown = tonumber(monitor.unknown) or 0,
    avg_uptime_24h = uptime(history.up_24h, history.total_24h),
    avg_uptime_7d = uptime(history.up_7d, history.total_7d),
    avg_uptime_30d = uptime(history.up_30d, history.total_30d),
  }
end

local function standalone_incidents(limit)
  local rows = db_query([[
    SELECT h.monitor_id, m.name, m.url, h.is_up, h.status_code, h.checked_at
    FROM (
      SELECT monitor_id, checked_at, is_up, status_code,
             LAG(is_up) OVER (PARTITION BY monitor_id ORDER BY checked_at) AS prev_is_up
      FROM check_history
    ) h
    JOIN monitors m ON m.id = h.monitor_id
    WHERE h.prev_is_up IS NOT NULL AND h.is_up != h.prev_is_up
    ORDER BY h.checked_at DESC
    LIMIT ?
  ]], { limit })
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = {
      monitor_id = r.monitor_id,
      name = r.name,
      url = r.url,
      status = (r.is_up == 1 or r.is_up == "1") and "UP" or "DOWN",
      status_code = r.status_code,
      at = r.checked_at,
    }
  end
  return out
end

local function needs_attention(now, limit)
  local rows = db_query([[
    SELECT id, name, url, is_up, last_status_code, last_response_time_ms, last_check_at,
           interval_sec
    FROM monitors
    WHERE enabled = 1
      AND (
        is_up = 0 OR
        last_check_at IS NULL OR
        (? - last_check_at) > MAX(COALESCE(interval_sec, 300) * 2, 60)
      )
    ORDER BY CASE WHEN is_up = 0 THEN 0 ELSE 1 END,
             CASE WHEN last_check_at IS NULL THEN 0 ELSE last_check_at END ASC
    LIMIT ?
  ]], { now, limit })
  local out = {}
  for _, r in ipairs(rows) do
    local stale = not r.last_check_at or (now - r.last_check_at) > math.max((tonumber(r.interval_sec) or 300) * 2, 60)
    out[#out + 1] = {
      monitor_id = r.id,
      name = r.name,
      url = r.url,
      reason = r.is_up == 0 and "DOWN" or (stale and "STALE" or "UNKNOWN"),
      status = r.is_up == 0 and "DOWN" or "UNKNOWN",
      status_code = r.last_status_code,
      last_response_time_ms = r.last_response_time_ms,
      last_check_at = r.last_check_at,
    }
  end
  return out
end

local function slowest_monitors(now, limit)
  local rows = db_query([[
    SELECT m.id, m.name, m.url,
           AVG(h.response_time_ms) as avg_response_time_ms,
           COUNT(h.id) as samples
    FROM monitors m
    JOIN check_history h ON h.monitor_id = m.id
    WHERE m.enabled = 1
      AND h.checked_at >= ?
      AND h.response_time_ms > 0
    GROUP BY m.id
    ORDER BY avg_response_time_ms DESC
    LIMIT ?
  ]], { now - 86400, limit })
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = {
      monitor_id = r.id,
      name = r.name,
      url = r.url,
      avg_response_time_ms = math.floor((tonumber(r.avg_response_time_ms) or 0) * 10) / 10,
      samples = tonumber(r.samples) or 0,
    }
  end
  return out
end

local function node_health(now)
  local liveness_row = db_first("SELECT value FROM settings WHERE key = ?", { "node_liveness_sec" })
  local liveness = tonumber(liveness_row and liveness_row.value) or 90
  local rows = db_query([[
    SELECT id, name, role, active, last_seen_at
    FROM nodes
    WHERE role != 'central'
    ORDER BY name ASC
  ]])
  local out = {}
  for _, r in ipairs(rows) do
    local status = r.active == 0 and "inactive"
      or (not r.last_seen_at or now - r.last_seen_at > liveness) and "stale"
      or "online"
    out[#out + 1] = {
      id = r.id,
      name = r.name,
      role = r.role,
      active = r.active,
      last_seen_at = r.last_seen_at,
      status = status,
    }
  end
  return out
end

local function central_incidents(limit)
  local rows = db_query([[
    SELECT cms.monitor_id, m.name, m.url, cms.current_status, cms.last_transition_at
    FROM cluster_monitor_state cms
    JOIN monitors m ON m.id = cms.monitor_id
    WHERE cms.current_status = 'DOWN'
    ORDER BY cms.last_transition_at DESC
    LIMIT ?
  ]], { limit })
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = {
      monitor_id = r.monitor_id,
      name = r.name,
      url = r.url,
      status = r.current_status,
      at = r.last_transition_at,
    }
  end
  return out
end

function M.get_global_stats(role)
  role = role or runtime_config.role()
  local now = os.time()
  local aggregates = global_aggregates(now)

  return {
    generated_at = now,
    aggregates = {
      total = aggregates.total,
      enabled = aggregates.enabled,
      disabled = aggregates.disabled,
      up = aggregates.up,
      down = aggregates.down,
      unknown = aggregates.unknown,
      active_incidents = aggregates.down,
      avg_uptime_24h = aggregates.avg_uptime_24h,
      avg_uptime_7d = aggregates.avg_uptime_7d,
      avg_uptime_30d = aggregates.avg_uptime_30d,
    },
    series = global_series(30),
    incidents = role == "central" and central_incidents(20) or standalone_incidents(20),
    attention = needs_attention(now, 10),
    slowest = slowest_monitors(now, 5),
    nodes = role == "central" and node_health(now) or {},
  }
end

return M
