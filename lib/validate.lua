local M = {}

-- ─── Primitives ──────────────────────────────────────────────

local function is_string(v) return type(v) == "string" end
local function is_number(v) return type(v) == "number" end

-- ─── String validators ───────────────────────────────────────

M.string = {}

function M.string.required(v, name)
    if not is_string(v) or v == "" then
        return name .. " is required"
    end
    return nil
end

function M.string.max_length(v, max, name)
    if v and #v > max then
        return name .. " must be at most " .. max .. " characters"
    end
    return nil
end

function M.string.one_of(v, allowed, name)
    if v == nil then
        return nil
    end
    for _, a in ipairs(allowed) do
        if v == a then
            return nil
        end
    end
    return name .. " must be one of: " .. table.concat(allowed, ", ")
end

function M.string.is_url(v, name)
    if v == nil then
        return nil
    end
    if not is_string(v) then
        return name .. " must be a string"
    end
    if not v:match("^https?://") then
        return name .. " must start with http:// or https://"
    end
    if #v > 2048 then
        return name .. " must be at most 2048 characters"
    end
    return nil
end

function M.string.is_json(v, name)
    if v == nil then
        return nil
    end
    if not is_string(v) then
        return name .. " must be a string"
    end
    local ok = pcall(function()
        json_decode(v)
    end)
    if not ok then
        return name .. " must be valid JSON"
    end
    return nil
end

-- ─── Number validators ───────────────────────────────────────

M.number = {}

function M.number.required(v, name)
    if not is_number(v) then
        return name .. " is required and must be a number"
    end
    return nil
end

function M.number.integer(v, name)
    if v == nil then
        return nil
    end
    if not is_number(v) or v % 1 ~= 0 then
        return name .. " must be an integer"
    end
    return nil
end

function M.number.range(v, min, max, name)
    if v == nil then
        return nil
    end
    if v < min or v > max then
        return name .. " must be between " .. min .. " and " .. max
    end
    return nil
end

function M.number.positive(v, name)
    if v == nil then
        return nil
    end
    if not is_number(v) or v <= 0 then
        return name .. " must be a positive number"
    end
    return nil
end

-- ─── Boolean coercion ────────────────────────────────────────

M.boolean = {}

function M.boolean.coerce(v)
    if v == 1 or v == "1" or v == true or v == "true" then
        return 1
    end
    if v == 0 or v == "0" or v == false or v == "false" then
        return 0
    end
    return nil
end

-- ─── Helper: run rules, return first error ───────────────────

local function check(data, rules)
    for _, rule in ipairs(rules) do
        local err = rule.fn(data[rule.field], table.unpack(rule.args))
        if err then
            return nil, err
        end
    end
    return true
end

-- ─── Monitor ─────────────────────────────────────────────────

function M.monitor_create(data)
    local ok, err = check(data, {
        { field = "name", fn = M.string.required, args = { "name" } },
        { field = "name", fn = M.string.max_length, args = { 255, "name" } },
        { field = "url",  fn = M.string.required, args = { "url" } },
        { field = "url",  fn = M.string.is_url, args = { "url" } },
    })
    if not ok then
        return nil, err
    end

    if data.method ~= nil then
        local e = M.string.one_of(data.method, { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" }, "method")
        if e then
            return nil, e
        end
    end

    for _, field in ipairs({ "interval_sec", "timeout_ms", "cert_threshold_days" }) do
        if data[field] ~= nil then
            local e = M.number.integer(data[field], field)
            if e then
                return nil, e
            end
        end
    end
    if data.interval_sec ~= nil then
        local e = M.number.range(data.interval_sec, 10, 86400, "interval_sec")
        if e then
            return nil, e
        end
    end
    if data.timeout_ms ~= nil then
        local e = M.number.range(data.timeout_ms, 1000, 60000, "timeout_ms")
        if e then
            return nil, e
        end
    end
    if data.cert_threshold_days ~= nil then
        local e = M.number.range(data.cert_threshold_days, 1, 365, "cert_threshold_days")
        if e then
            return nil, e
        end
    end
    if data.check_value ~= nil then
        local e = M.string.max_length(data.check_value, 1000, "check_value")
        if e then
            return nil, e
        end
    end

    return {
        name = data.name,
        url = data.url,
        method = data.method,
        interval_sec = data.interval_sec,
        timeout_ms = data.timeout_ms,
        check_value = data.check_value or "",
        enabled = M.boolean.coerce(data.enabled) or 1,
        desktop_notify = M.boolean.coerce(data.desktop_notify) or 0,
        check_cert = M.boolean.coerce(data.check_cert) or 0,
        cert_threshold_days = data.cert_threshold_days,
    }
end

function M.monitor_update(data)
    for _, field in ipairs({ "interval_sec", "timeout_ms", "cert_threshold_days" }) do
        if data[field] ~= nil then
            local e = M.number.integer(data[field], field)
            if e then
                return nil, e
            end
        end
    end
    if data.interval_sec ~= nil then
        local e = M.number.range(data.interval_sec, 10, 86400, "interval_sec")
        if e then
            return nil, e
        end
    end
    if data.timeout_ms ~= nil then
        local e = M.number.range(data.timeout_ms, 1000, 60000, "timeout_ms")
        if e then
            return nil, e
        end
    end
    if data.cert_threshold_days ~= nil then
        local e = M.number.range(data.cert_threshold_days, 1, 365, "cert_threshold_days")
        if e then
            return nil, e
        end
    end
    if data.url ~= nil then
        local e = M.string.is_url(data.url, "url")
        if e then
            return nil, e
        end
    end
    if data.method ~= nil then
        local e = M.string.one_of(data.method, { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" }, "method")
        if e then
            return nil, e
        end
    end
    if data.check_value ~= nil then
        local e = M.string.max_length(data.check_value, 1000, "check_value")
        if e then
            return nil, e
        end
    end
    if data.name ~= nil then
        local e = M.string.max_length(data.name, 255, "name")
        if e then
            return nil, e
        end
    end

    local out = {}
    for _, field in ipairs({ "name", "url", "method", "interval_sec", "timeout_ms", "check_value", "enabled", "desktop_notify", "check_cert", "cert_threshold_days" }) do
        if data[field] ~= nil then
            if field == "enabled" or field == "desktop_notify" or field == "check_cert" then
                out[field] = M.boolean.coerce(data[field])
            else
                out[field] = data[field]
            end
        end
    end
    return out
end

-- ─── Channel ─────────────────────────────────────────────────

function M.channel_create(data)
    local ok, err = check(data, {
        { field = "name",   fn = M.string.required, args = { "name" } },
        { field = "name",   fn = M.string.max_length, args = { 255, "name" } },
        { field = "type",   fn = M.string.required, args = { "type" } },
        { field = "type",   fn = M.string.one_of, args = { { "webhook", "discord", "slack", "ntfy", "email" }, "type" } },
        { field = "config", fn = M.string.required, args = { "config" } },
        { field = "config", fn = M.string.is_json, args = { "config" } },
    })
    if not ok then
        return nil, err
    end

    return {
        name = data.name,
        type = data.type,
        config = data.config,
        enabled = M.boolean.coerce(data.enabled) or 1,
    }
end

function M.channel_update(data)
    if data.name ~= nil then
        local e = M.string.max_length(data.name, 255, "name")
        if e then
            return nil, e
        end
    end
    if data.type ~= nil then
        local e = M.string.one_of(data.type, { "webhook", "discord", "slack", "ntfy", "email" }, "type")
        if e then
            return nil, e
        end
    end
    if data.config ~= nil then
        local e = M.string.is_json(data.config, "config")
        if e then
            return nil, e
        end
    end

    local out = {}
    for _, field in ipairs({ "name", "type", "config", "enabled" }) do
        if data[field] ~= nil then
            if field == "enabled" then
                out[field] = M.boolean.coerce(data[field])
            else
                out[field] = data[field]
            end
        end
    end
    return out
end

-- ─── Settings ────────────────────────────────────────────────

function M.settings_update(data)
    local range_rules = {
        { field = "retention_days",       min = 1,   max = 3650 },
        { field = "alert_cooldown_sec",   min = 60,  max = 86400 },
        { field = "node_liveness_sec",    min = 30,  max = 3600 },
        { field = "consensus_min_nodes",  min = 1,   max = 100 },
        { field = "consensus_quorum_pct", min = 1,   max = 100 },
    }
    for _, r in ipairs(range_rules) do
        if data[r.field] ~= nil then
            local e = M.number.positive(data[r.field], r.field)
            if e then
                return nil, e
            end
            e = M.number.range(data[r.field], r.min, r.max, r.field)
            if e then
                return nil, e
            end
        end
    end

    if data.treat_4xx_as_down ~= nil then
        local v = M.boolean.coerce(data.treat_4xx_as_down)
        if v == nil then
            return nil, "treat_4xx_as_down must be 0 or 1"
        end
    end
    if data.instance_name ~= nil then
        local e = M.string.max_length(data.instance_name, 100, "instance_name")
        if e then
            return nil, e
        end
    end
    if data.status_page_theme ~= nil then
        local e = M.string.one_of(data.status_page_theme, { "light", "dark" }, "status_page_theme")
        if e then
            return nil, e
        end
    end

    return data
end

-- ─── Node ────────────────────────────────────────────────────

function M.node_create(data)
    if not data.name or data.name == "" then
        return nil, "name is required"
    end
    return { name = data.name }
end

function M.node_update(data)
    if data.name ~= nil then
        if not is_string(data.name) or data.name == "" then
            return nil, "name must be a non-empty string"
        end
        return { name = data.name }
    end
    return {}
end

-- ─── Status Page ─────────────────────────────────────────────

function M.status_page_create(data)
    local ok, err = check(data, {
        { field = "type", fn = M.string.required, args = { "type" } },
        { field = "type", fn = M.string.one_of, args = { { "monitor", "group" }, "type" } },
        { field = "name", fn = M.string.required, args = { "name" } },
        { field = "name", fn = M.string.max_length, args = { 255, "name" } },
    })
    if not ok then
        return nil, err
    end

    if data.type == "monitor" and not data.monitor_id then
        return nil, "monitor_id is required for monitor-type pages"
    end

    return {
        type = data.type,
        name = data.name,
        description = data.description or "",
        is_public = data.is_public,
        monitor_id = data.monitor_id,
    }
end

function M.status_page_update(data)
    if data.type ~= nil then
        local e = M.string.one_of(data.type, { "monitor", "group" }, "type")
        if e then
            return nil, e
        end
    end
    if data.name ~= nil then
        if data.name == "" then
            return nil, "name must not be empty"
        end
        local e = M.string.max_length(data.name, 255, "name")
        if e then
            return nil, e
        end
    end

    local out = {}
    for _, field in ipairs({ "type", "name", "description", "is_public", "monitor_id" }) do
        if data[field] ~= nil then
            out[field] = data[field]
        end
    end
    return out
end

-- ─── Report ──────────────────────────────────────────────────

function M.report_payload(data)
    if not data.reports or type(data.reports) ~= "table" then
        return nil, "reports array is required"
    end
    if #data.reports > 100 then
        return nil, "reports batch too large (max 100)"
    end

    local out = { reports = {} }
    for i, r in ipairs(data.reports) do
        if not r.monitor_id then
            return nil, "monitor_id required in report #" .. i
        end
        if r.is_up == nil then
            return nil, "is_up required in report #" .. i
        end
        table.insert(out.reports, {
            monitor_id = tonumber(r.monitor_id) or r.monitor_id,
            is_up = r.is_up,
            status_code = r.status_code,
            response_time_ms = r.response_time_ms,
            error_message = r.error_message,
        })
    end
    return out
end

return M
