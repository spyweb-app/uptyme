local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local validate = require("lib.validate")

local M = {}

function M.get(self)
    local s = db.get_settings()
    s.role = runtime_config.role()
    return H.json_response(200, s)
end

function M.update(self)
    local data, err = H.parse_body(self)
    if not data then return err end

    local validated, val_err = H.validate_or_400(data, validate.settings_update)
    if not validated then return val_err end

    local settings, write_err = db.update_settings(validated)
    if not settings then
        return H.json_response(400, nil, write_err or "Failed to update settings")
    end
    return H.json_response(200, settings)
end

return M
