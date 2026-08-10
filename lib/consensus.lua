local db = require("lib.db")
local notifier = require("lib.notifier")

local M = {}

function M.evaluate(monitor_id, is_up_snapshot, settings)
	local now = os.time()
	
	-- Early return: skip full evaluation if report matches current state
	if is_up_snapshot ~= nil then
		local state = db.get_monitor_consensus_state(monitor_id)
		if state and ((is_up_snapshot == 1 and state.current_status == "UP") or (is_up_snapshot == 0 and state.current_status == "DOWN")) then
			db.update_consensus_state_timestamp(monitor_id, now)
			return { transition = false, status = state.current_status, skipped = true }
		end
	end
	
	settings = settings or db.get_settings()
	local liveness_sec = tonumber(settings.node_liveness_sec) or 90
	local min_nodes = tonumber(settings.consensus_min_nodes) or 2
	local quorum_pct = tonumber(settings.consensus_quorum_pct) or 51
	
	local rows = db.get_nodes_with_reports(monitor_id)
	if #rows == 0 then return { transition = false } end
	
	local live_count = 0
	local down_votes = 0
	
	for _, row in ipairs(rows) do
		if row.last_seen_at and (now - row.last_seen_at) <= liveness_sec then
			live_count = live_count + 1
			if row.is_up == 0 then
				down_votes = down_votes + 1
			end
		end
	end
	
	if live_count == 0 then return { transition = false } end
	
	local threshold = math.min(min_nodes, math.ceil(live_count * quorum_pct / 100))
	local is_down = down_votes >= threshold
	local new_status = is_down and "DOWN" or "UP"
	
	local state = db.get_monitor_consensus_state(monitor_id)
	
	if not state then
		db.insert_consensus_state(monitor_id, new_status, now)
		return { transition = false, status = new_status }
	end
	
	if state.current_status ~= new_status then
		local monitor = db.get(monitor_id)
		if monitor then
			notifier.dispatch(monitor_id, {
				monitor = monitor.name,
				url = monitor.url,
				severity = new_status,
				message = "Cluster consensus: " .. down_votes .. "/" .. live_count .. " nodes report " .. new_status,
				timestamp = now,
			})
		end
		
		db.update_consensus_state(monitor_id, new_status, now)
		
		return { transition = true, status = new_status, down_votes = down_votes, live_count = live_count }
	end
	
	db.update_consensus_state_timestamp(monitor_id, now)
	return { transition = false, status = state.current_status }
end

return M
