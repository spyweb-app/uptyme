local runtime_config = require("lib.runtime_config")

local M = {}

local function numeric(value)
  return tonumber(value)
end

function M.normalize_status(is_up, status_code)
  is_up = numeric(is_up)
  status_code = numeric(status_code)
  if is_up == nil then return "unknown" end
  if is_up == 0 then return "down" end
  if status_code and status_code >= 400 and status_code < 500 then return "blocked" end
  return "operational"
end

local function status_rank(status)
  return ({ operational = 1, unknown = 2, blocked = 3, down = 4 })[status] or 2
end

local function worse_status(current, candidate)
  if not current or status_rank(candidate) > status_rank(current) then return candidate end
  return current
end

local function current_state(row)
  local is_up = row.is_up
  local status_code = row.last_status_code

  -- A central node with reports uses the consensus result. A local monitor
  -- state remains the fallback until a checker has actually reported.
  if runtime_config.is_central() and numeric(row.has_reports) == 1 and row.current_status then
    is_up = row.current_status == "UP" and 1 or 0
  end

  return M.normalize_status(is_up, status_code)
end

local function monitor_result(row, status)
    return {
        monitor_id = tonumber(row.monitor_id),
        name = row.public_name or row.monitor_name,
        slug = row.public_slug,
        status = status,
    last_checked_at = row.last_check_at,
  }
end

local function monitor_page_row(page_id)
  local now = os.time()
  return db_first(string.format([[
    SELECT sp.id AS page_id, sp.slug, sp.name AS public_name,
           sp.description, sp.type, sp.is_public,
           m.id AS monitor_id, m.name AS monitor_name, m.is_up,
           m.last_status_code, m.last_response_time_ms, m.last_check_at,
           m.interval_sec,
           cs.current_status, cs.last_transition_at,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) AS up_24h,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) AS total_24h,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) AS up_7d,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) AS total_7d,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d AND is_up = 1) AS up_30d,
           (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= %d) AS total_30d
    FROM status_pages sp
    JOIN monitors m ON m.id = sp.monitor_id
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    WHERE sp.id = ? AND sp.type = 'monitor' AND sp.is_public = 1
      AND m.enabled = 1
  ]], now - 86400, now - 86400, now - 604800, now - 604800, now - 2592000, now - 2592000), { page_id })
end

function M.get_public_monitor_status(page_id, month)
  if runtime_config.is_checker() then return nil end
  local row = monitor_page_row(page_id)
  if not row then return nil end
  local status = current_state(row)

  local function calc_uptime(up, total)
    up = tonumber(up) or 0
    total = tonumber(total) or 0
    return total > 0 and math.floor((up / total) * 100) or nil
  end

  local result = monitor_result(row, status)
  result.description = row.description
  result.last_response_time_ms = tonumber(row.last_response_time_ms)
  result.last_status_code = tonumber(row.last_status_code)
  result.interval_sec = tonumber(row.interval_sec)
  result.uptime_24h = calc_uptime(row.up_24h, row.total_24h)
  result.uptime_7d = calc_uptime(row.up_7d, row.total_7d)
  result.uptime_30d = calc_uptime(row.up_30d, row.total_30d)

  local monitor_id = tonumber(row.monitor_id)
  local monitors_db = require("lib.db.monitors")

  if month then
    local now = os.time()
    local y, m = month:match("^(%d+)%-(%d+)$")
    if y and m then
      local month_start = os.time({ year = tonumber(y), month = tonumber(m), day = 1, hour = 0 })
      local days = math.ceil((now - month_start) / 86400) + 31
      local summary = monitors_db.get_summary(monitor_id, days, "day")
      local prefix = month .. "-"
      local filtered = {}
      for _, s in ipairs(summary) do
        if s.period:sub(1, #prefix) == prefix then
          filtered[#filtered + 1] = s
        end
      end
      result.summary = filtered
    else
      result.summary = monitors_db.get_summary(monitor_id, 30, "day")
    end
  else
    result.summary = monitors_db.get_summary(monitor_id, 30, "day")
  end

  result.history = monitors_db.get_history(monitor_id, os.time(), 100)

  return result
end

local function member_rows(page_id)
  return db_query([[
    SELECT sp.id AS page_id, sp.slug, sp.name AS group_name,
           sp.description, sp.type, sp.is_public,
           spm.monitor_id, spm.display_order,
           m.name AS monitor_name, m.is_up, m.last_status_code,
           m.last_response_time_ms, m.last_check_at,
           cs.current_status, cs.last_transition_at,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports,
           public_page.slug AS public_slug
    FROM status_pages sp
    JOIN status_page_monitors spm ON spm.status_page_id = sp.id
    JOIN monitors m ON m.id = spm.monitor_id
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    LEFT JOIN status_pages public_page
      ON public_page.monitor_id = m.id
     AND public_page.type = 'monitor'
     AND public_page.is_public = 1
    WHERE sp.id = ? AND sp.type = 'group' AND sp.is_public = 1
      AND m.enabled = 1
    ORDER BY spm.display_order ASC, m.name ASC, m.id ASC
  ]], { page_id })
end

local function standalone_incident_starts(ids)
  if #ids == 0 then return {} end
  local placeholders = {}
  for _ = 1, #ids do placeholders[#placeholders + 1] = "?" end
  local rows = db_query([[
    SELECT h.monitor_id, MIN(h.checked_at) AS started_at
    FROM check_history h
    WHERE h.monitor_id IN (]] .. table.concat(placeholders, ",") .. [[)
      AND h.is_up = 0
      AND h.checked_at > COALESCE((
        SELECT MAX(recovery.checked_at)
        FROM check_history recovery
        WHERE recovery.monitor_id = h.monitor_id AND recovery.is_up = 1
      ), 0)
    GROUP BY h.monitor_id
  ]], ids)
  local out = {}
  for _, row in ipairs(rows) do out[tonumber(row.monitor_id)] = row.started_at end
  return out
end

function M.get_public_group_status(page_id, month)
  if runtime_config.is_checker() then return nil end
  local page = db_first([[SELECT id, slug, name, description, type, is_public
    FROM status_pages WHERE id = ? AND type = 'group' AND is_public = 1]], { page_id })
  if not page then return nil end

  local rows = member_rows(page_id)
  local ids = {}
  local members = {}
  local overall
  local counts = { operational = 0, blocked = 0, down = 0, unknown = 0 }
  for _, row in ipairs(rows) do
    local status = current_state(row)
    ids[#ids + 1] = tonumber(row.monitor_id)
    members[#members + 1] = monitor_result(row, status)
    counts[status] = counts[status] + 1
    overall = worse_status(overall, status)
  end

  if #members == 0 then overall = "unknown" end

  if #ids > 0 then
    local monitors_db = require("lib.db.monitors")
    local days = 30
    local prefix
    if month then
      local y, m = month:match("^(%d+)%-(%d+)$")
      if y and m then
        local now = os.time()
        local month_start = os.time({ year = tonumber(y), month = tonumber(m), day = 1, hour = 0 })
        days = math.ceil((now - month_start) / 86400) + 31
        prefix = month .. "-"
      end
    end

    local summary_rows = monitors_db.get_summary(ids, days, "day")
    local by_monitor = {}
    for _, row in ipairs(summary_rows) do
      local mid = tonumber(row.monitor_id)
      if prefix and row.period:sub(1, #prefix) ~= prefix then
        -- skip rows outside the requested month
      else
        if not by_monitor[mid] then by_monitor[mid] = {} end
        by_monitor[mid][#by_monitor[mid] + 1] = row
      end
    end
    for _, m in ipairs(members) do
      m.summary = by_monitor[m.monitor_id] or {}
    end
  end

  local starts = standalone_incident_starts(ids)
  local incidents = {}
  for i, row in ipairs(rows) do
    local status = members[i].status
    if status == "down" then
      local started_at = row.last_transition_at
      if not (runtime_config.is_central() and tonumber(row.has_reports) == 1) then
        started_at = starts[tonumber(row.monitor_id)]
      end
      incidents[#incidents + 1] = {
        monitor_id = tonumber(row.monitor_id),
        name = row.monitor_name,
        status = "down",
        started_at = started_at,
      }
    end
  end

  return {
    name = page.name,
    description = page.description,
    slug = page.slug,
    status = overall,
    monitor_count = #members,
    operational_count = counts.operational,
    blocked_count = counts.blocked,
    down_count = counts.down,
    unknown_count = counts.unknown,
    monitors = members,
    incidents = incidents,
  }
end

return M
