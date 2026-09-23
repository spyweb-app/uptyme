local M = {}

-- ─── Coercion ────────────────────────────────────────────────

local function coerce_int(v, name)
    if type(v) == "number" then
        if v % 1 ~= 0 then
            return nil, name .. " must be an integer"
        end
        return v
    end
    if type(v) ~= "string" or not v:match("^%-?%d+$") then
        return nil, name .. " must be an integer"
    end
    return tonumber(v)
end

local function coerce_string(v, name)
    if type(v) == "string" then return v end
    if type(v) == "number" then return tostring(v) end
    return nil, name .. " must be a string"
end

local function coerce_bool(v, name)
    if v == 1 or v == "1" or v == true or v == "true" then
        return 1
    end
    if v == 0 or v == "0" or v == false or v == "false" then
        return 0
    end
    return nil, name .. " must be 0 or 1"
end

local function check_semantics(v, rule, field)
    if rule.type == "int" then
        if rule.min and v < rule.min then
            return field .. " must be between " .. rule.min .. " and " .. rule.max
        end
        if rule.max and v > rule.max then
            return field .. " must be between " .. rule.min .. " and " .. rule.max
        end
    elseif rule.type == "string" then
        if rule.max and #v > rule.max then
            return field .. " must be at most " .. rule.max .. " characters"
        end
        if rule.enum then
            local ok = false
            for _, a in ipairs(rule.enum) do
                if v == a then
                    ok = true
                    break
                end
            end
            if not ok then
                return field .. " must be one of: " .. table.concat(rule.enum, ", ")
            end
        end
        if rule.url then
            if not v:match("^https?://") then
                return field .. " must start with http:// or https://"
            end
            if #v > 2048 then
                return field .. " must be at most 2048 characters"
            end
        end
        if rule.json then
            local ok = pcall(function()
                json_decode(v)
            end)
            if not ok then
                return field .. " must be valid JSON"
            end
        end
    end
    return nil
end

local function run(data, schema, opts)
    opts = opts or {}
    local partial = opts.partial
    local out = {}

    for field, rule in pairs(schema) do
        local v = data[field]

        if v == nil then
            if not partial then
                if rule.required then
                    return nil, field .. " is required"
                end
                if rule.default ~= nil then
                    out[field] = rule.default
                end
            end
        else
            local cv, err

            if rule.type == "int" then
                cv, err = coerce_int(v, field)
            elseif rule.type == "bool" then
                cv, err = coerce_bool(v, field)
            elseif rule.type == "string" then
                if rule.coerce == false then
                    if type(v) == "string" then
                        cv = v
                    else
                        err = field .. " must be a string"
                    end
                else
                    cv, err = coerce_string(v, field)
                end
            else
                cv = v
            end

            if err then
                return nil, err
            end

            if cv == "" then
                if not partial and rule.required then
                    return nil, field .. " is required"
                end
                if rule.nonempty then
                    return nil, rule.nonempty
                end
            end

            err = check_semantics(cv, rule, field)
            if err then
                return nil, err
            end

            out[field] = cv
        end
    end

    return out
end

-- ─── Schemas ────────────────────────────────────────────────

local MONITOR = {
    name                = { type = "string", required = true, max = 255 },
    url                 = { type = "string", coerce = false, required = true, url = true },
    method              = { type = "string", enum = { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" } },
    interval_sec        = { type = "int", min = 10, max = 86400 },
    timeout_ms          = { type = "int", min = 1000, max = 60000 },
    check_value         = { type = "string", max = 1000, default = "" },
    enabled             = { type = "bool", default = 1 },
    desktop_notify      = { type = "bool", default = 0 },
    check_cert          = { type = "bool", default = 0 },
    cert_threshold_days = { type = "int", min = 0, max = 365, default = 0 },
}

local CHANNEL = {
    name   = { type = "string", required = true, max = 255 },
    type   = { type = "string", required = true, enum = { "webhook", "discord", "slack", "ntfy", "email" } },
    config = { type = "string", coerce = false, required = true, json = true },
    enabled = { type = "bool", default = 1 },
}

local SETTINGS = {
    instance_name               = { type = "string", max = 100 },
    status_page_slug_style      = { type = "string", enum = { "name_random", "random" } },
    status_page_theme           = { type = "string", enum = { "light", "dark" } },
    retention_days              = { type = "int", min = 1, max = 3650 },
    alert_cooldown_sec          = { type = "int", min = 60, max = 86400 },
    node_liveness_sec           = { type = "int", min = 30, max = 3600 },
    consensus_min_nodes         = { type = "int", min = 1, max = 100 },
    consensus_quorum_pct        = { type = "int", min = 1, max = 100 },
    cert_threshold_days         = { type = "int", min = 1, max = 365 },
    status_page_random_length   = { type = "int", min = 3, max = 10 },
    status_page_name_max_length = { type = "int", min = 5, max = 50 },
    treat_4xx_as_down           = { type = "bool" },
}

local NODE = {
    name = { type = "string", required = true, nonempty = "name must be a non-empty string" },
}

local STATUS_PAGE = {
    type        = { type = "string", required = true, enum = { "monitor", "group" } },
    name        = { type = "string", required = true, max = 255, nonempty = "name must not be empty" },
    description = { type = "string", default = "" },
    monitor_id  = { type = "int" },
    is_public   = { type = "bool" },
}

local REPORT = {
    monitor_id       = { type = "int", required = true },
    is_up            = { type = "bool", required = true },
    status_code      = { type = "int" },
    response_time_ms = { type = "int" },
    error_message    = {},
}

-- ─── Monitor ────────────────────────────────────────────────

function M.monitor_create(data)
    return run(data, MONITOR, {})
end

function M.monitor_update(data)
    return run(data, MONITOR, { partial = true })
end

-- ─── Channel ────────────────────────────────────────────────

function M.channel_create(data)
    return run(data, CHANNEL, {})
end

function M.channel_update(data)
    return run(data, CHANNEL, { partial = true })
end

-- ─── Settings ───────────────────────────────────────────────

function M.settings_update(data)
    return run(data, SETTINGS, { partial = true })
end

-- ─── Node ───────────────────────────────────────────────────

function M.node_create(data)
    return run(data, NODE, {})
end

function M.node_update(data)
    return run(data, NODE, { partial = true })
end

-- ─── Status Page ────────────────────────────────────────────

function M.status_page_create(data)
    local out, err = run(data, STATUS_PAGE, {})
    if not out then return nil, err end
    if out.type == "monitor" and not out.monitor_id then
        return nil, "monitor_id is required for monitor-type pages"
    end
    return out
end

function M.status_page_update(data)
    return run(data, STATUS_PAGE, { partial = true })
end

-- ─── Report ─────────────────────────────────────────────────

function M.report_payload(data)
    if not data.reports or type(data.reports) ~= "table" then
        return nil, "reports array is required"
    end
    if #data.reports > 100 then
        return nil, "reports batch too large (max 100)"
    end

    local out = { reports = {} }
    for i, r in ipairs(data.reports) do
        if type(r) ~= "table" then
            return nil, "report #" .. i .. " must be an object"
        end

        local entry, err = run(r, REPORT, {})
        if not entry then
            return nil, err .. " in report #" .. i
        end
        table.insert(out.reports, entry)
    end
    return out
end

return M
