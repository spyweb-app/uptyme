local H = require("helpers")
local consensus = require("lib.consensus")
local db = require("lib.db")

local M = {}

function M.report(self, node)
	
	local data = json_decode(self.body or "")
	if not data or not data.reports or type(data.reports) ~= "table" then
		return H.json_response(400, nil, "reports array required")
	end
	
	local settings = db.get_settings()
	local batch = {}
	local valid_reports = {}
	local results = {}
	for _, r in ipairs(data.reports) do
		local mid = tonumber(r.monitor_id)
		if not mid or r.is_up == nil then
			table.insert(results, { monitor_id = mid, error = "invalid report" })
		else
			local is_up = r.is_up
			local code = tonumber(r.status_code)
			if is_up == 1 and code and code >= 400 and code < 500
				and (tonumber(settings.treat_4xx_as_down) or 0) == 1 then
				is_up = 0
			end
			table.insert(batch, {
				monitor_id = mid,
				node_id = node.id,
				is_up = is_up,
				status_code = r.status_code,
				response_time_ms = r.response_time_ms,
				error_message = r.error_message,
			})
			table.insert(valid_reports, { monitor_id = mid, is_up = is_up })
		end
	end
	
	db.upsert_node_reports_batch(batch)
	
	for _, report in ipairs(valid_reports) do
		local res = consensus.evaluate(report.monitor_id, report.is_up, settings)
		table.insert(results, {
			monitor_id = report.monitor_id,
			transition = res.transition,
			status = res.status,
			skipped = res.skipped,
		})
	end
	
	return H.json_response(200, { results = results })
end

return M
