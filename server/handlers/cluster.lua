local db = require("lib.db")

local M = {}

function M.version(self, node)
    return { status = 200, body = tostring(db.get_monitors_version()) }
end

function M.export(self, node)
    return { status = 200, body = json_encode(db.export_syncable()) }
end

return M
