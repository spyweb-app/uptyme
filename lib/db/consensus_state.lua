local M = {}

function M.get_monitor_consensus_state(monitor_id)
  local rows = db_query("SELECT * FROM cluster_monitor_state WHERE monitor_id = ?", { monitor_id })
  return rows[1]
end

function M.insert_consensus_state(monitor_id, new_status, now)
  db_exec("INSERT INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at) VALUES (?, ?, ?, ?)",
    { monitor_id, new_status, now, now })
end

function M.update_consensus_state(monitor_id, new_status, now)
  db_exec("UPDATE cluster_monitor_state SET current_status = ?, last_transition_at = ?, last_alerted_status = ?, last_alerted_at = ?, updated_at = ? WHERE monitor_id = ?",
    { new_status, now, new_status, now, now, monitor_id })
end

function M.update_consensus_state_timestamp(monitor_id, now)
  db_exec("UPDATE cluster_monitor_state SET updated_at = ? WHERE monitor_id = ?", { now, monitor_id })
end

function M.seed_consensus_state(monitor_id)
  db_exec("INSERT OR IGNORE INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at) VALUES (?, 'UP', ?, ?)",
    { monitor_id, os.time(), os.time() })
end

return M
