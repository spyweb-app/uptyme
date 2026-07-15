local M = {}

function M.list_channels()
  return db_query("SELECT * FROM notification_channels ORDER BY name ASC")
end

function M.get_channel(id)
  local rows = db_query("SELECT * FROM notification_channels WHERE id = ?", { id })
  return rows[1]
end

function M.create_channel(data)
  local ok, err = pcall(db_exec, "INSERT INTO notification_channels (name, type, config, enabled) VALUES (?, ?, ?, ?)", {
    data.name,
    data.type,
    data.config or "{}",
    data.enabled == nil and 1 or (data.enabled ~= 0 and 1 or 0)
  })
  if not ok then return nil, err end
  local rows = db_query("SELECT * FROM notification_channels WHERE id = last_insert_rowid()")
  return rows[1]
end

function M.update_channel(id, data)
  local sets = {}
  local params = {}
  local updatable = { "name", "type", "config", "enabled" }
  for _, field in ipairs(updatable) do
    if data[field] ~= nil then
      table.insert(sets, field .. " = ?")
      table.insert(params, data[field])
    end
  end
  if #sets == 0 then return M.get_channel(id) end
  table.insert(params, id)
  db_exec("UPDATE notification_channels SET " .. table.concat(sets, ", ") .. " WHERE id = ?", params)
  return M.get_channel(id)
end

function M.delete_channel(id)
  db_exec("DELETE FROM notification_channels WHERE id = ?", { id })
end

function M.get_monitor_channel_ids(monitor_id)
  local rows = db_query("SELECT channel_id FROM monitor_notifications WHERE monitor_id = ?", { monitor_id })
  local ids = {}
  for _, r in ipairs(rows) do
    table.insert(ids, r.channel_id)
  end
  return ids
end

function M.set_monitor_channels(monitor_id, ids)
  db_exec("DELETE FROM monitor_notifications WHERE monitor_id = ?", { monitor_id })
  for _, channel_id in ipairs(ids or {}) do
    db_exec("INSERT INTO monitor_notifications (monitor_id, channel_id) VALUES (?, ?)", { monitor_id, channel_id })
  end
end

function M.get_alert_channels(monitor_id)
  return db_query([[
    SELECT c.* FROM notification_channels c
    JOIN monitor_notifications mn ON mn.channel_id = c.id
    WHERE mn.monitor_id = ? AND c.enabled = 1
  ]], { monitor_id })
end

return M
