local alert = require("alert")
local db = require("lib.db")

local M = {}

function M.classify_status(fetch_result)
    if not fetch_result.ok and not fetch_result.response then
        return {
            is_up = 0,
            severity = "DOWN",
            status_code = 0,
            err = (fetch_result.error and fetch_result.error.message) or "unknown"
        }
    end
    
    if fetch_result.response then
        local status = fetch_result.response.status
        
        if status >= 500 then
            return { is_up = 0, severity = "DOWN", status_code = status }
        elseif status >= 400 then
            return { is_up = 1, severity = "BLOCKED", status_code = status }
        elseif status >= 200 then
            return { is_up = 1, severity = "UP", status_code = status }
        else
            return { is_up = 0, severity = "DOWN", status_code = status }
        end
    end
    
    return { is_up = 0, severity = "DOWN", status_code = 0, err = "unknown error" }
end

function M.check_content(body, value)
    if not value or value == "" then return nil end
    if not body then
        return { is_up = 0, err = "No response body to check" }
    end
    if not body:find(value, 1, true) then
        return { is_up = 0, err = "Expected content not found: " .. value }
    end
    return nil
end

function M.run(fetch_result, shared)
    local now = os.time()
    local response_time_ms = (fetch_result.response and fetch_result.response.time_ms) or 0
    
    local r = M.classify_status(fetch_result)
    local is_up, severity, status_code, err_msg = r.is_up, r.severity, r.status_code, r.err or ""
    
    if is_up == 1 and shared.check_value ~= "" then
        local cc = M.check_content(fetch_result.response and fetch_result.response.body, shared.check_value)
        if cc then
            is_up, severity, err_msg = 0, "DOWN", cc.err
        end
    end

    if severity == "BLOCKED" and db.get_int("treat_4xx_as_down", 0) == 1 then
        is_up, severity = 0, "DOWN"
    end

    local new_failures = alert.compute_failures(is_up, severity, shared.prev_failures)
    
    return {
        is_up = is_up,
        severity = severity,
        status_code = status_code,
        err_msg = err_msg,
        new_failures = new_failures,
        response_time_ms = response_time_ms,
        now = now,
    }
end

return M
