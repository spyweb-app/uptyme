local H = require("helpers")
local db = require("lib.db")
local notifier = require("lib.notifier")
local validate = require("lib.validate")

local M = {}

function M.list(self)
    return H.json_response(200, db.list_channels())
end

function M.create(self)
    local denied = H.reject_checker_mutation("Notification channels")
    if denied then return denied end

    local data, err = H.parse_body(self)
    if not data then return err end

    local validated, val_err = H.validate_or_400(data, validate.channel_create)
    if not validated then return val_err end

    local row, db_err = db.create_channel(validated)
    if not row then
        return H.json_response(500, nil, "Failed to create: " .. tostring(db_err))
    end

    return H.json_response(201, row)
end

function M.test(self)
    local id, id_err = H.require_id(self, "Channel")
    if not id then return id_err end

    local row, row_err = H.find_or_404(db.get_channel, id, "Channel")
    if not row then return row_err end

    local body = json_decode(self.body or "{}")
    local msg = (type(body) == "table" and body.message) or "Test notification from PULSE"
    local ok, resp = notifier.dispatch_to_channel(id, {
        monitor = "Test",
        url = "",
        severity = "UP",
        message = msg,
        timestamp = os.time(),
    })
    if not ok then
        return H.json_response(500, nil, "Test failed: " .. tostring(resp))
    end
    if type(resp) == "table" and resp.status and resp.status >= 400 then
        return H.json_response(200, {
            name = row.name,
            type = row.type,
            response = resp,
            error = "HTTP " .. resp.status,
        })
    end
    return H.json_response(200, { name = row.name, type = row.type, response = resp })
end

function M.update(self)
    local id, id_err = H.require_id(self, "Channel")
    if not id then return id_err end

    if self.path_args[2] == "test" then
        return M.test(self)
    end

    local denied = H.reject_checker_mutation("Notification channels")
    if denied then return denied end

    local data, err = H.parse_body(self)
    if not data then return err end

    local validated, val_err = H.validate_or_400(data, validate.channel_update)
    if not validated then return val_err end

    local row = db.get_channel(id)
    if not row then
        return H.json_response(404, nil, "Channel not found")
    end

    row = db.update_channel(id, validated)
    return H.json_response(200, row)
end

function M.remove(self)
    local id, id_err = H.require_id(self, "Channel")
    if not id then return id_err end

    local denied = H.reject_checker_mutation("Notification channels")
    if denied then return denied end

    local row, row_err = H.find_or_404(db.get_channel, id, "Channel")
    if not row then return row_err end

    db.delete_channel(id)
    return H.deleted()
end

return M
