local H = require("helpers")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")

local M = {}

function M.version(self)
    local node = cluster_auth.verify(self)
    if not node then
        return H.json_response(401, nil, "Unauthorized")
    end

    return { status = 200, body = tostring(db.get_monitors_version()) }
end

function M.export(self)
    local node = cluster_auth.verify(self)
    if not node then
        return H.json_response(401, nil, "Unauthorized")
    end

    return H.json_response(200, db.export_syncable())
end

return M
