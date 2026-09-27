local M = {}

local STATE_COLS = "monitor_id, current_status, last_transition_at, last_alerted_status, last_alerted_at, updated_at"
local STATE_UPDATABLE = { "current_status", "last_transition_at", "last_alerted_status", "last_alerted_at", "updated_at" }

function M.get_monitor_consensus_state(monitor_id)
  return db_select_one("cluster_monitor_state", STATE_COLS, "monitor_id", monitor_id)
end

function M.insert_consensus_state(monitor_id, new_status, now)
  db_exec("INSERT INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at) VALUES (?, ?, ?, ?)",
    { monitor_id, new_status, now, now })
end

function M.update_consensus_state(monitor_id, new_status, now)
  db_update_by_id("cluster_monitor_state", monitor_id, {
    current_status = new_status,
    last_transition_at = now,
    last_alerted_status = new_status,
    last_alerted_at = now,
    updated_at = now,
  }, STATE_UPDATABLE, { key = "monitor_id" })
end

function M.update_consensus_state_timestamp(monitor_id, now)
  db_update_by_id("cluster_monitor_state", monitor_id, { updated_at = now }, { "updated_at" }, { key = "monitor_id" })
end

function M.insert_consensus_transition(monitor_id, status, transitioned_at)
  db_exec("INSERT INTO consensus_transitions (monitor_id, status, transitioned_at) VALUES (?, ?, ?)",
    { monitor_id, status, transitioned_at })
end

function M.cleanup_old_transitions(days)
  local cutoff = os.time() - (days * 86400)
  return db_exec("DELETE FROM consensus_transitions WHERE transitioned_at < ?", { cutoff })
end

return M
