local normalize = require("lib.monitor_util").normalize

local M = {}

function M.csv_escape(s)
    if not s then return "" end
    if s:find('[,%"\n]') then
        return '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

function M.parse_csv_row(line)
    local fields = {}
    local current = ""
    local in_quotes = false
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            if in_quotes then
                local next = line:sub(i+1, i+1)
                if next == '"' then
                    current = current .. '"'
                    i = i + 1
                else
                    in_quotes = false
                end
            else
                in_quotes = true
            end
        elseif c == ',' and not in_quotes then
            fields[#fields+1] = current
            current = ""
        else
            current = current .. c
        end
        i = i + 1
    end
    fields[#fields+1] = current
    return fields
end

function M.parse_csv(body)
    local lines = {}
    for line in body:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines < 2 then return nil end
    if lines[1]:match("[%[{%]}]") then return nil end

    local headers = M.parse_csv_row(lines[1])
    if not headers then return nil end
    local header_map = {}
    for i, h in ipairs(headers) do
        header_map[h:lower()] = i
    end

    local required = header_map["name"] and header_map["url"]
    if not required then return nil end

    local results = {}
    for i = 2, #lines do
        local fields = M.parse_csv_row(lines[i])
        table.insert(results, {
            name = fields[header_map["name"]],
            url = fields[header_map["url"]],
            method = fields[header_map["method"]],
            interval_sec = tonumber(fields[header_map["interval_sec"]]),
            timeout_ms = tonumber(fields[header_map["timeout_ms"]]),
            check_value = fields[header_map["check_value"]],
            desktop_notify = tonumber(fields[header_map["desktop_notify"]]),
            enabled = tonumber(fields[header_map["enabled"]]),
            check_cert = tonumber(fields[header_map["check_cert"]]),
            cert_threshold_days = tonumber(fields[header_map["cert_threshold_days"]]),
        })
    end
    return results
end

function M.export_csv(rows)
    local lines = { "name,url,method,interval_sec,timeout_ms,check_value,desktop_notify,enabled,check_cert,cert_threshold_days" }
    for _, m in ipairs(rows) do
        local n = normalize(m)
        table.insert(lines, table.concat({
            M.csv_escape(m.name),
            M.csv_escape(m.url),
            M.csv_escape(n.method),
            tostring(n.interval_sec),
            tostring(n.timeout_ms),
            M.csv_escape(n.check_value),
            tostring(n.desktop_notify),
            tostring(n.enabled),
            tostring(n.check_cert),
            tostring(n.cert_threshold_days),
        }, ","))
    end
    return table.concat(lines, "\n")
end

function M.parse_import(body)
    local parsed = json_decode(body)
    if type(parsed) == "table" then
        return parsed[1] and parsed or { parsed }
    end
    return M.parse_csv(body)
end

function M.validate_entry(entry)
    if type(entry) ~= "table" then return false end
    if not entry.name or entry.name == "" then return false end
    if not entry.url or entry.url == "" then return false end
    return true
end

return M
