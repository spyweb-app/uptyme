local M = {}

local runtime_config = require("lib.runtime_config")

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

function M.parse_body(self)
    local data = json_decode(self.body or "")
    if not data or type(data) ~= "table" then
        return nil, M.json_response(400, nil, "Invalid JSON body")
    end
    return data
end

function M.reject_checker_mutation(resource)
    if runtime_config.is_checker() then
        return M.json_response(403, nil, (resource or "Resource") .. " are managed on the central node")
    end
    return nil
end

function M.validate_or_400(data, validator)
    local validated, err = validator(data)
    if not validated then
        return nil, M.json_response(400, nil, err)
    end
    return validated
end

function M.require_id(self, label)
    local id = tonumber(self.path_args[1])
    if not id then
        return nil, M.json_response(400, nil, (label or "Resource") .. " ID required")
    end
    return id
end

function M.find_or_404(fetch_fn, id, label)
    local row = fetch_fn(id)
    if not row then
        return nil, M.json_response(404, nil, (label or "Resource") .. " not found")
    end
    return row
end

function M.deleted()
    return M.json_response(200, { deleted = true })
end

return M
