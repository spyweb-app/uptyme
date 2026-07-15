local runtime_config = require("lib.runtime_config")

local M = {}

function M.get_settings()
  local rows = db_query("SELECT key, value FROM settings")
  local settings = {}
  for _, row in ipairs(rows) do
    settings[row.key] = row.value
  end

  if runtime_config.enabled() then
    local bootstrap = runtime_config.bootstrap_settings()
    for key, value in pairs(bootstrap) do
      if settings[key] == nil or settings[key] == "" then
        settings[key] = value
      end
    end
  end

  return settings
end

function M.update_settings(data)
  for key, value in pairs(data) do
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", { key, tostring(value) })
  end
  return M.get_settings()
end

function M.get_retention_days()
  local rows = db_query("SELECT value FROM settings WHERE key = 'retention_days'")
  return tonumber(rows[1] and rows[1].value) or 90
end

function M.get_alert_cooldown_sec()
  local rows = db_query("SELECT value FROM settings WHERE key = 'alert_cooldown_sec'")
  return tonumber(rows[1] and rows[1].value) or 300
end

function M.get_cert_threshold_days()
  local rows = db_query("SELECT value FROM settings WHERE key = 'cert_threshold_days'")
  return tonumber(rows[1] and rows[1].value) or 14
end

function M.get_monitors_version()
  local rows = db_query("SELECT value FROM settings WHERE key = 'monitors_version'")
  return tonumber(rows[1] and rows[1].value) or 0
end

function M.bump_monitors_version()
  db_exec("UPDATE settings SET value = CAST(value AS INTEGER) + 1 WHERE key = 'monitors_version'")
end

function M.get_consensus_min_nodes()
  local rows = db_query("SELECT value FROM settings WHERE key = 'consensus_min_nodes'")
  return tonumber(rows[1] and rows[1].value) or 2
end

function M.get_consensus_quorum_pct()
  local rows = db_query("SELECT value FROM settings WHERE key = 'consensus_quorum_pct'")
  return tonumber(rows[1] and rows[1].value) or 51
end

return M
