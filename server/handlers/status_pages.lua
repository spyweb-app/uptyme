local H = require("helpers")
local db = require("lib.db")
local validate = require("lib.validate")

local M = {}

function M.list(self)
    if self.path_args[1] then
        local id, id_err = H.require_id(self, "Status page")
        if not id then return id_err end
        if self.query.view == "monitors" then
            if not db.get_status_page(id) then
                return H.json_response(404, nil, "Status page not found")
            end
            return H.json_response(200, db.list_status_page_monitors(id))
        end
        return H.json_response(200, db.get_status_page(id))
    end
    return H.json_response(200, db.list_status_pages())
end

function M.create(self)
    local denied = H.reject_checker_mutation("Status pages")
    if denied then return denied end

    local data, err = H.parse_body(self)
    if not data then return err end

    local validated, val_err = H.validate_or_400(data, validate.status_page_create)
    if not validated then return val_err end

    local row, db_err = db.create_status_page(validated)
    if not row then
        return H.json_response(db_err == "monitor not found" and 404 or 400, nil, db_err)
    end
    return H.json_response(201, row)
end

function M.update(self)
    local denied = H.reject_checker_mutation("Status pages")
    if denied then return denied end

    local id, id_err = H.require_id(self, "Status page")
    if not id then return id_err end

    local data, parse_err = H.parse_body(self)
    if not data then return parse_err end

    local monitors = data.monitors
    if monitors ~= nil then
        if type(monitors) ~= "table" then
            return H.json_response(400, nil, "monitors must be an array")
        end
        local seen = {}
        for i, m in ipairs(monitors) do
            local mid = type(m) == "table" and tonumber(m.monitor_id) or nil
            if not mid or mid < 1 or mid ~= math.floor(mid) then
                return H.json_response(400, nil, "monitors[" .. i .. "].monitor_id must be a positive integer")
            end
            if seen[mid] then
                return H.json_response(400, nil, "duplicate monitor_id " .. mid)
            end
            seen[mid] = true
        end
    end

    local validated, val_err = H.validate_or_400(data, validate.status_page_update)
    if not validated then return val_err end

    if monitors ~= nil then
        local ok, m_err = db.set_status_page_monitors(id, monitors)
        if not ok then
            local code = (m_err == "status page not found" or m_err == "monitor not found") and 404 or 400
            return H.json_response(code, nil, m_err)
        end
    end

    local row, db_err = db.update_status_page(id, validated)
    if not row then return H.json_response(404, nil, db_err) end
    return H.json_response(200, row)
end

function M.remove(self)
    local denied = H.reject_checker_mutation("Status pages")
    if denied then return denied end

    local id, id_err = H.require_id(self, "Status page")
    if not id then return id_err end

    if not db.get_status_page(id) then
        return H.json_response(404, nil, "Status page not found")
    end
    db.delete_status_page(id)
    return H.deleted()
end

return M
