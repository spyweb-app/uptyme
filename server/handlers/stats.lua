local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")

local M = {}

function M.get(self)
    if runtime_config.is_checker() then
        return H.json_response(404, nil, "Stats are not available on a checker node")
    end
    return H.json_response(200, db.get_global_stats(runtime_config.role()))
end

return M