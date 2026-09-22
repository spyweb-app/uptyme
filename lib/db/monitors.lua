local normalize = require("lib.monitor_util").normalize
local runtime_config = require("lib.runtime_config")

local M = {}

-- Helpers shared by multiple functions in this module

local ALLOWED_SORTS = {
  name = "m.name",
  url = "m.url",
  is_up = "m.is_up",
  last_check_at = "m.last_check_at",
}

-- Returns the effective is_up value for a monitor row.
-- For central nodes with consensus tracking, uses cluster_monitor_state.current_status.
-- For standalone or untracked monitors, returns the raw is_up from the monitors table.
local function effective_is_up(row)
  local is_up = row.is_up
  if runtime_config.is_central() and row.has_reports == 1 and row.current_status then
    is_up = row.current_status == "UP" and 1 or 0
  end
  return is_up
end

local function effective_is_up_expr(tracked_ids, alias)
  alias = alias or "h"
  if #tracked_ids == 0 then return alias .. ".is_up" end
  local tracked_literal = {}
  for _, id in ipairs(tracked_ids) do tracked_literal[#tracked_literal + 1] = tostring(id) end
  return string.format([[
    CASE WHEN %s.monitor_id IN (%s)
         THEN CASE WHEN COALESCE(
           (SELECT ct.status FROM consensus_transitions ct
            WHERE ct.monitor_id = %s.monitor_id AND ct.transitioned_at <= %s.checked_at
            ORDER BY ct.transitioned_at DESC LIMIT 1),
           'UP'
         ) = 'UP' THEN 1 ELSE 0 END
         ELSE %s.is_up
    END
  ]], alias, table.concat(tracked_literal, ","), alias, alias, alias)
end

-- Query

function M.list_all()
  local rows = db_query([[
    SELECT m.*, cs.current_status,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM monitors m
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    ORDER BY m.created_at DESC
  ]])
  if #rows > 0 then
    for _, m in ipairs(rows) do m.is_up = effective_is_up(m) end
    local ids = {}
    for _, m in ipairs(rows) do ids[#ids + 1] = m.id end
    local uptime = M.get_uptime(ids, { 1, 7, 30 })
    for _, m in ipairs(rows) do
      local u = uptime[m.id] or {}
      m.uptime_24h = u[1]
      m.uptime_7d = u[7]
      m.uptime_30d = u[30]
    end
  end
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

  local all_params = {}
  for _, v in ipairs(where_params) do all_params[#all_params + 1] = v end

  local offset = (page - 1) * per_page
  all_params[#all_params + 1] = per_page
  all_params[#all_params + 1] = offset

  local rows = db_query([[
    SELECT m.*, cs.current_status,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM monitors m
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
  ]] .. where_clause .. " ORDER BY " .. sort_col .. " " .. order_dir .. " LIMIT ? OFFSET ?", all_params)

  for _, m in ipairs(rows) do m.is_up = effective_is_up(m) end

  if #rows > 0 then
    local ids = {}
    for _, m in ipairs(rows) do ids[#ids + 1] = m.id end
    local uptime = M.get_uptime(ids, { 1, 7, 30 })
    for _, m in ipairs(rows) do
      local u = uptime[m.id] or {}
      m.uptime_24h = u[1]
      m.uptime_7d = u[7]
      m.uptime_30d = u[30]
    end
  end

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
  local row = db_first([[
    SELECT m.*, cs.current_status,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM monitors m
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    WHERE m.id = ?
  ]], { id })
  if row then row.is_up = effective_is_up(row) end
  return row
end

function M.get_by_url(url)
  return db_first("SELECT * FROM monitors WHERE url = ?", { url })
end

local function consensus_tracked_ids(ids)
  if not runtime_config.is_central() then return {} end
  local placeholders = {}
  for _ = 1, #ids do placeholders[#placeholders + 1] = "?" end
  local rows = db_query(
    "SELECT DISTINCT monitor_id FROM node_reports WHERE monitor_id IN (" .. table.concat(placeholders, ",") .. ")",
    ids)
  local out = {}
  for _, r in ipairs(rows) do out[tonumber(r.monitor_id)] = true end
  return out
end

function M.get_history(id, before, limit)
  local tracked = consensus_tracked_ids({ id })
  if tracked[id] then
    local eiu = effective_is_up_expr({ id }, "h")
    return db_query(string.format([[
      SELECT id, monitor_id, status_code, response_time_ms,
        %s as is_up,
        error_message, checked_at
      FROM check_history h
      WHERE monitor_id = ? AND checked_at < ?
      ORDER BY checked_at DESC
      LIMIT ?
    ]], eiu), { id, before, limit })
  end
  return db_query([[
    SELECT id, monitor_id, status_code, response_time_ms, is_up, error_message, checked_at
    FROM check_history
    WHERE monitor_id = ? AND checked_at < ?
    ORDER BY checked_at DESC
    LIMIT ?
  ]], { id, before, limit })
end

local function summary_range(monitor_ids, since, until_, group_unit)
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

  local tracked = consensus_tracked_ids(ids)
  local tracked_ids = {}
  for _, id in ipairs(ids) do
    if tracked[id] then tracked_ids[#tracked_ids + 1] = id end
  end

  local eiu = effective_is_up_expr(tracked_ids, "h")

  local params = {}
  for _, id in ipairs(ids) do params[#params + 1] = id end
  params[#params + 1] = since
  local upper_bound = ""
  if until_ then
    params[#params + 1] = until_
    upper_bound = " AND h.checked_at < ?"
  end

  return db_query(string.format([[
    SELECT %s%s as period,
           COUNT(*) as total,
           SUM(%s) as up_count,
           SUM(CASE WHEN %s = 0 THEN 1 ELSE 0 END) as down_checks,
           SUM(CASE WHEN %s = 1 AND h.status_code >= 400
                    AND h.status_code < 500 THEN 1 ELSE 0 END) as blocked_checks,
           AVG(CASE WHEN h.response_time_ms > 0 THEN h.response_time_ms END) as avg_response_ms
    FROM %s
    WHERE %s AND h.checked_at >= ?%s
    GROUP BY %s
    ORDER BY %s
  ]], monitor_col, period_expr, eiu, eiu, eiu, "check_history h", where, upper_bound, group_by, order_by), params)
end

function M.get_summary(monitor_ids, days, group_unit)
  local since = os.time() - (days * 86400)
  return summary_range(monitor_ids, since, nil, group_unit)
end

function M.get_summary_range(monitor_ids, since, until_, group_unit)
  return summary_range(monitor_ids, since, until_, group_unit)
end

function M.get_months(monitor_id)
  local rows = db_query([[
    SELECT DISTINCT strftime('%Y-%m', checked_at, 'unixepoch') AS month
    FROM check_history
    WHERE monitor_id = ?
    ORDER BY month DESC
  ]], { monitor_id })
  local months = {}
  for _, row in ipairs(rows) do
    months[#months + 1] = row.month
  end
  return months
end

function M.get_uptime(monitor_ids, windows)
  local ids = type(monitor_ids) == "table" and monitor_ids or { monitor_ids }
  local tracked = consensus_tracked_ids(ids)
  local tracked_ids = {}
  for _, id in ipairs(ids) do
    if tracked[id] then tracked_ids[#tracked_ids + 1] = id end
  end
  local eiu = effective_is_up_expr(tracked_ids, "h")

  local placeholders = {}
  for _ = 1, #ids do placeholders[#placeholders + 1] = "?" end
  local where = "m.id IN (" .. table.concat(placeholders, ",") .. ")"

  local select_parts = {}
  local now = os.time()
  for _, days in ipairs(windows) do
    local since = now - (days * 86400)
    select_parts[#select_parts + 1] = string.format(
      "(SELECT ROUND(CAST(SUM(%s) AS REAL) * 100 / NULLIF(COUNT(*), 0), 1) FROM check_history h WHERE h.monitor_id = m.id AND h.checked_at >= %d) as uptime_%dd",
      eiu, since, days)
  end

  local query = string.format("SELECT m.id, %s FROM monitors m WHERE %s GROUP BY m.id",
    table.concat(select_parts, ", "), where)

  local params = {}
  for _, id in ipairs(ids) do params[#params + 1] = id end

  local rows = db_query(query, params)
  local out = {}
  for _, r in ipairs(rows) do
    local mid = tonumber(r.id)
    out[mid] = {}
    for _, days in ipairs(windows) do
      out[mid][days] = tonumber(r[string.format("uptime_%dd", days)])
    end
  end
  return out
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
  db_exec("DELETE FROM cluster_monitor_state WHERE monitor_id = ?", { id })
  db_exec("DELETE FROM consensus_transitions WHERE monitor_id = ?", { id })
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
  db_exec(
    "UPDATE monitors SET cert_not_after = ?, cert_days_left = ?, cert_last_check = ?, updated_at = ? WHERE id = ?",
    { not_after or "", days_left or 0, checked_at, os.time(), monitor_id }
  )
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
  local all_ids = {}
  local all_rows = db_query("SELECT id FROM monitors")
  for _, r in ipairs(all_rows) do all_ids[#all_ids + 1] = r.id end
  local tracked = consensus_tracked_ids(all_ids)
  local tracked_ids = {}
  for _, id in ipairs(all_ids) do
    if tracked[id] then tracked_ids[#tracked_ids + 1] = id end
  end
  local eiu = effective_is_up_expr(tracked_ids, "h")

  local rows = db_query(string.format([[
    SELECT date(checked_at, 'unixepoch') as period,
           COUNT(*) as total,
           SUM(%s) as up_count
    FROM check_history h
    WHERE checked_at >= ?
    GROUP BY period
    ORDER BY period ASC
  ]], eiu), { since })
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
  local monitor_rows = db_query([[
    SELECT m.id, m.enabled, m.is_up,
           cs.current_status,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM monitors m
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
  ]])

  local total, enabled, disabled, up_count, down_count, unknown_count = 0, 0, 0, 0, 0, 0
  local all_ids = {}
  for _, row in ipairs(monitor_rows) do
    total = total + 1
    if row.enabled == 1 then enabled = enabled + 1 else disabled = disabled + 1 end
    if row.enabled == 1 then
      local is_up = effective_is_up(row)
      if is_up == 1 then up_count = up_count + 1
      elseif is_up == 0 then down_count = down_count + 1
      else unknown_count = unknown_count + 1 end
    end
    all_ids[#all_ids + 1] = row.id
  end
  local tracked = consensus_tracked_ids(all_ids)
  local tracked_ids = {}
  for _, id in ipairs(all_ids) do
    if tracked[id] then tracked_ids[#tracked_ids + 1] = id end
  end
  local eiu = effective_is_up_expr(tracked_ids, "h")

  local history = db_first(string.format([[
    SELECT
      SUM(CASE WHEN checked_at >= ? AND %s = 1 THEN 1 ELSE 0 END) as up_24h,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_24h,
      SUM(CASE WHEN checked_at >= ? AND %s = 1 THEN 1 ELSE 0 END) as up_7d,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_7d,
      SUM(CASE WHEN checked_at >= ? AND %s = 1 THEN 1 ELSE 0 END) as up_30d,
      SUM(CASE WHEN checked_at >= ? THEN 1 ELSE 0 END) as total_30d
    FROM check_history h
  ]], eiu, eiu, eiu), {
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
    total = total,
    enabled = enabled,
    disabled = disabled,
    up = up_count,
    down = down_count,
    unknown = unknown_count,
    avg_uptime_24h = uptime(history.up_24h, history.total_24h),
    avg_uptime_7d = uptime(history.up_7d, history.total_7d),
    avg_uptime_30d = uptime(history.up_30d, history.total_30d),
  }
end

local function pair_incidents(transitions)
  local by_monitor = {}
  for _, t in ipairs(transitions) do
    local mid = tonumber(t.monitor_id)
    if not by_monitor[mid] then by_monitor[mid] = { name = t.name, url = t.url, rows = {} } end
    by_monitor[mid].rows[#by_monitor[mid].rows + 1] = t
  end

  local incidents = {}
  for mid, data in pairs(by_monitor) do
    local rows = data.rows
    local i = 1
    while i <= #rows do
      local row_status = rows[i].status
      if row_status == "DOWN" or row_status == "down" or row_status == 0 then
        local started_at = rows[i].transitioned_at or rows[i].checked_at
        local resolved_at = nil
        local status_code = rows[i].status_code
        local next = rows[i + 1]
        if next then
          local next_status = next.status
          if next_status == "UP" or next_status == "up" or next_status == 1 then
            resolved_at = next.transitioned_at or next.checked_at
            i = i + 2
          else
            i = i + 1
          end
        else
          i = i + 1
        end
        incidents[#incidents + 1] = {
          monitor_id = mid,
          name = data.name,
          url = data.url,
          status = resolved_at and "UP" or "DOWN",
          started_at = started_at,
          resolved_at = resolved_at,
          status_code = status_code,
        }
      else
        i = i + 1
      end
    end
  end

  table.sort(incidents, function(a, b) return (a.started_at or 0) > (b.started_at or 0) end)
  return incidents
end

function M.get_incidents(monitor_ids, limit, role)
  if runtime_config.is_checker() then return {} end
  if monitor_ids and #monitor_ids == 0 then return {} end

  role = role or runtime_config.role()
  local transitions

  if role == "central" then
    local where = ""
    local params = {}
    if monitor_ids then
      local placeholders = {}
      for _ = 1, #monitor_ids do placeholders[#placeholders + 1] = "?" end
      where = "WHERE ct.monitor_id IN (" .. table.concat(placeholders, ",") .. ")"
      for _, id in ipairs(monitor_ids) do params[#params + 1] = id end
    end
    transitions = db_query([[
      SELECT monitor_id, name, url, status, transitioned_at
      FROM (
        SELECT ct.id AS transition_id, ct.monitor_id, m.name, m.url, ct.status,
               ct.transitioned_at,
               ROW_NUMBER() OVER (
                 PARTITION BY ct.monitor_id
                 ORDER BY ct.transitioned_at DESC, ct.id DESC
               ) AS rn
        FROM consensus_transitions ct
        JOIN monitors m ON m.id = ct.monitor_id
        ]] .. where .. [[
      ) limited
      WHERE rn <= 40
      ORDER BY monitor_id, transitioned_at, transition_id
    ]], params)
  else
    local where = ""
    local params = {}
    if monitor_ids then
      local placeholders = {}
      for _ = 1, #monitor_ids do placeholders[#placeholders + 1] = "?" end
      where = "AND h.monitor_id IN (" .. table.concat(placeholders, ",") .. ")"
      for _, id in ipairs(monitor_ids) do params[#params + 1] = id end
    end
    transitions = db_query([[
      SELECT monitor_id, name, url, status, status_code, transitioned_at
      FROM (
        SELECT h.transition_id, h.monitor_id, m.name, m.url,
               h.status, h.status_code, h.transitioned_at,
               ROW_NUMBER() OVER (
                 PARTITION BY h.monitor_id
                 ORDER BY h.transitioned_at DESC, h.transition_id DESC
               ) AS rn
        FROM (
          SELECT id AS transition_id, monitor_id, checked_at AS transitioned_at,
                 is_up AS status, status_code,
                 LAG(is_up) OVER (
                   PARTITION BY monitor_id ORDER BY checked_at, id
                 ) AS prev_is_up
          FROM check_history
        ) h
        JOIN monitors m ON m.id = h.monitor_id
        WHERE h.prev_is_up IS NOT NULL AND h.status != h.prev_is_up
          ]] .. where .. [[
      ) limited
      WHERE rn <= 40
      ORDER BY monitor_id, transitioned_at, transition_id
    ]], params)
  end

  local incidents = pair_incidents(transitions)
  if limit then
    local limited = {}
    for i = 1, math.min(limit, #incidents) do limited[i] = incidents[i] end
    return limited
  end
  return incidents
end

local function needs_attention(now, limit)
  local rows = db_query([[
    SELECT m.id, m.name, m.url, m.is_up, m.last_status_code, m.last_response_time_ms,
           m.last_check_at, m.interval_sec,
           cs.current_status,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM monitors m
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    WHERE m.enabled = 1
  ]])
  local out = {}
  for _, r in ipairs(rows) do
    local is_up = effective_is_up(r)
    local stale = not r.last_check_at or (now - r.last_check_at) > math.max((tonumber(r.interval_sec) or 300) * 2, 60)
    local needs = is_up == 0 or not r.last_check_at or stale
    if needs then
      out[#out + 1] = {
        monitor_id = r.id,
        name = r.name,
        url = r.url,
        reason = is_up == 0 and "DOWN" or (stale and "STALE" or "UNKNOWN"),
        status = is_up == 0 and "DOWN" or "UNKNOWN",
        status_code = r.last_status_code,
        last_response_time_ms = r.last_response_time_ms,
        last_check_at = r.last_check_at,
      }
    end
  end
  table.sort(out, function(a, b)
    if (a.status == "DOWN") ~= (b.status == "DOWN") then return a.status == "DOWN" end
    return (a.last_check_at or 0) < (b.last_check_at or 0)
  end)
  if #out > limit then
    local limited = {}
    for i = 1, limit do limited[i] = out[i] end
    return limited
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
    incidents = M.get_incidents(nil, 100, role),
    attention = needs_attention(now, 100),
    slowest = slowest_monitors(now, 5),
    nodes = role == "central" and node_health(now) or {},
  }
end

return M
