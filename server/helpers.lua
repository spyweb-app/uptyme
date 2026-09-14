local M = {}

function M.json_response(status, data, err)
    local res = { success = status < 400, data = data, error = err }
    return { status = status, body = json_encode(res, true), headers = { ["Content-Type"] = "application/json" } }
end

function M.id_or_nil(args)
    return tonumber(args[1])
end

function M.int_param(query, key, default)
    local val = query[key]
    if not val then return default end
    return tonumber(val) or default
end

function M.str_param(query, key, default)
    local val = query[key]
    if not val then return default end
    return val
end

return M
