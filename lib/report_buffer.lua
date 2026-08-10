local M = {}

local buffer = {}

function M.push(report)
	table.insert(buffer, report)
end

function M.flush()
	local reports = buffer
	buffer = {}
	return reports
end

return M
