local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")

local M = {}

function M.get(self)
    local s = db.get_settings()
    s.role = runtime_config.role()
    return H.json_response(200, s)
end

function M.update(self)
    local data = json_decode(self.body or "")
    if not data or type(data) ~= "table" then
        return H.json_response(400, nil, "Invalid JSON body")
    end

    local settings = db.update_settings(data)
    return H.json_response(200, settings)
end

return M
