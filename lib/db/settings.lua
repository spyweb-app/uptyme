local M = {}

function M.get_settings()
  local rows = db_query("SELECT key, value FROM settings")
  local settings = {}
  for _, row in ipairs(rows) do
    settings[row.key] = row.value
  end
  return settings
end

function M.update_settings(data)
  -- Allowed setting keys (whitelist) to prevent arbitrary key injection
  local allowed_keys = {
    retention_days = true,
    alert_cooldown_sec = true,
    node_liveness_sec = true,
    consensus_min_nodes = true,
    consensus_quorum_pct = true,
    treat_4xx_as_down = true,
    instance_name = true,
    status_page_theme = true,
  }
  for key, value in pairs(data) do
    if not allowed_keys[key] then
      return nil, "Invalid setting key: " .. tostring(key)
    end
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", { key, tostring(value) })
  end
  return M.get_settings()
end

function M.get_setting(key, default)
  local row = db_first("SELECT value FROM settings WHERE key = ?", { key })
  if row then return row.value end
  return default
end

function M.get_int(key, default)
  local n = tonumber(M.get_setting(key))
  if n ~= nil then return n end
  return default
end

function M.get_monitors_version()
  return M.get_int("monitors_version", 0)
end

function M.bump_monitors_version()
  db_exec("UPDATE settings SET value = CAST(value AS INTEGER) + 1 WHERE key = 'monitors_version'")
end

return M
