local runtime_config = require("lib.runtime_config")

local M = {}

local function numeric(value)
  return tonumber(value)
end

local function month_bounds(month)
  if type(month) ~= "string" then return nil end
  local year, month_number = month:match("^(%d%d%d%d)%-(%d%d)$")
  year = tonumber(year)
  month_number = tonumber(month_number)
  if not year or not month_number or month_number < 1 or month_number > 12 then
    return nil
  end

  local row = db_first([[
    SELECT CAST(strftime('%s', ? || '-01 00:00:00') AS INTEGER) AS since,
           CAST(strftime('%s', date(? || '-01 00:00:00', '+1 month')) AS INTEGER) AS until_ts
  ]], { month, month })
  if not row or not row.since or not row.until_ts then return nil end
  return tonumber(row.since), tonumber(row.until_ts)
end

function M.resolve_window(opts)
  opts = opts or {}
  local month = opts.month
  local days = opts.days
  local group = opts.group

  if month ~= nil then
    local since, until_ = month_bounds(month)
    if not since then return nil, "Invalid month" end
    if days ~= nil then return nil, "month and days cannot be combined" end
    group = group or "day"
    if group ~= "day" and group ~= "hour" and group ~= "halfday" then
      return nil, "Invalid group"
    end
    return since, until_, group
  end

  days = days or 30
  if type(days) ~= "number" or days % 1 ~= 0 or days < 1 or days > 3650 then
    return nil, "Invalid days"
  end
  group = group or "day"
  if group ~= "day" and group ~= "hour" and group ~= "halfday" then
    return nil, "Invalid group"
  end
  return os.time() - (days * 86400), os.time(), group
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
  return db_first([[
    SELECT sp.id AS page_id, sp.slug AS public_slug, sp.name AS public_name,
           sp.description, sp.type, sp.is_public,
           m.id AS monitor_id, m.name AS monitor_name, m.is_up,
           m.last_status_code, m.last_response_time_ms, m.last_check_at,
           m.interval_sec,
           cs.current_status, cs.last_transition_at,
           EXISTS(SELECT 1 FROM node_reports nr WHERE nr.monitor_id = m.id) AS has_reports
    FROM status_pages sp
    JOIN monitors m ON m.id = sp.monitor_id
    LEFT JOIN cluster_monitor_state cs ON cs.monitor_id = m.id
    WHERE sp.id = ? AND sp.type = 'monitor' AND sp.is_public = 1
      AND m.enabled = 1
  ]], { page_id })
end

function M.get_public_monitor_status(page_id, month, days, group)
  if runtime_config.is_checker() then return nil end
  local row = monitor_page_row(page_id)
  if not row then return nil end
  local status = current_state(row)

  local monitor_id = tonumber(row.monitor_id)
  local monitors_db = require("lib.db.monitors")

  local uptime = monitors_db.get_uptime({ monitor_id }, { 1, 7, 30 })
  local u = uptime[monitor_id] or {}

  local result = monitor_result(row, status)
  result.description = row.description
  result.last_response_time_ms = tonumber(row.last_response_time_ms)
  result.last_status_code = tonumber(row.last_status_code)
  result.interval_sec = tonumber(row.interval_sec)
  result.uptime_24h = u[1]
  result.uptime_7d = u[7]
  result.uptime_30d = u[30]

  days = days or 30
  group = group or "day"

  if month then
    local since, until_ = month_bounds(month)
    if since then
      result.summary = monitors_db.get_summary_range(monitor_id, since, until_, group)
    else
      result.summary = monitors_db.get_summary(monitor_id, days, group)
    end
  else
    result.summary = monitors_db.get_summary(monitor_id, days, group)
  end

  result.incidents = monitors_db.get_incidents({ monitor_id }, nil)

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

  local monitors_db = require("lib.db.monitors")

  if #ids > 0 then
    local days = 30
    local since, until_
    if month then
      since, until_ = month_bounds(month)
    end

    local summary_rows
    if since then
      summary_rows = monitors_db.get_summary_range(ids, since, until_, "day")
    else
      summary_rows = monitors_db.get_summary(ids, days, "day")
    end
    local by_monitor = {}
    for _, row in ipairs(summary_rows) do
      local mid = tonumber(row.monitor_id)
      if not by_monitor[mid] then by_monitor[mid] = {} end
      by_monitor[mid][#by_monitor[mid] + 1] = row
    end
    for _, m in ipairs(members) do
      m.summary = by_monitor[m.monitor_id] or {}
    end
  end

  local incidents = monitors_db.get_incidents(ids, nil)

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

function M.get_public_report(slug, opts, monitor_id)
  if runtime_config.is_checker() then return nil, "Not found" end

  local page = db_first([[
    SELECT id, slug, type, monitor_id, is_public
    FROM status_pages WHERE slug = ?
  ]], { slug })
  if not page or page.is_public ~= 1 then return nil, "Not found" end

  local target_id
  if page.type == "monitor" then
    local row = db_first([[
      SELECT id FROM monitors WHERE id = ? AND enabled = 1
    ]], { page.monitor_id })
    if not row then return nil, "Not found" end
    target_id = tonumber(row.id)
  else
    if not monitor_id then return nil, "Not found" end
    local member = db_first([[
      SELECT 1 FROM status_page_monitors spm
      JOIN monitors m ON m.id = spm.monitor_id
      WHERE spm.status_page_id = ? AND spm.monitor_id = ? AND m.enabled = 1
    ]], { page.id, monitor_id })
    if not member then return nil, "Not found" end
    target_id = monitor_id
  end

  local since, until_, group = M.resolve_window(opts)
  if not since then return nil, until_ end

  local monitors_db = require("lib.db.monitors")
  return {
    summary = monitors_db.get_summary_range(target_id, since, until_, group),
    months = monitors_db.get_months(target_id),
  }
end

return M
