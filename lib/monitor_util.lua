local M = {}

function M.normalize(entry)
	return {
		method = entry.method or "HEAD",
		interval_sec = entry.interval_sec or 300,
		timeout_ms = entry.timeout_ms or 10000,
		check_value = entry.check_value or "",
		enabled = entry.enabled == nil and 1 or (entry.enabled ~= 0 and 1 or 0),
		desktop_notify = entry.desktop_notify == nil and 0 or (entry.desktop_notify ~= 0 and 1 or 0),
		check_cert = entry.check_cert == nil and 0 or (entry.check_cert ~= 0 and 1 or 0),
		cert_threshold_days = entry.cert_threshold_days or 14,
	}
end

return M
