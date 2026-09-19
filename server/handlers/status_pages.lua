local H = require("helpers")
local db = require("lib.db")
local validate = require("lib.validate")

local M = {}

function M.list(self)
    if self.path_args[1] then
        local id, id_err = H.require_id(self, "Status page")
        if not id then return id_err end
        if self.path_args[2] == "monitors" then
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

    if self.path_args[1] and self.path_args[2] == "monitors" then
        local id, id_err = H.require_id(self, "Status page")
        if not id then return id_err end
        local membership, m_err = db.add_status_page_monitor(id, data.monitor_id, data.display_order)
        if not membership then
            local code = (m_err == "status page not found" or m_err == "monitor not found") and 404 or 400
            return H.json_response(code, nil, m_err)
        end
        return H.json_response(201, membership)
    end

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

    if self.path_args[2] == "monitors" then
        local monitor_id = tonumber(self.path_args[3])
        if not monitor_id then return H.json_response(400, nil, "Monitor ID required") end
        local data, err = H.parse_body(self)
        if not data then return err end
        local row, u_err = db.update_status_page_monitor_order(id, monitor_id, data.display_order)
        if not row then return H.json_response(404, nil, u_err or "Membership not found") end
        return H.json_response(200, row)
    end

    local data, parse_err = H.parse_body(self)
    if not data then return parse_err end

    local validated, val_err = H.validate_or_400(data, validate.status_page_update)
    if not validated then return val_err end

    local row, db_err = db.update_status_page(id, validated)
    if not row then return H.json_response(404, nil, db_err) end
    return H.json_response(200, row)
end

function M.remove(self)
    local denied = H.reject_checker_mutation("Status pages")
    if denied then return denied end

    local id, id_err = H.require_id(self, "Status page")
    if not id then return id_err end

    if self.path_args[2] == "monitors" then
        local monitor_id = tonumber(self.path_args[3])
        if not monitor_id then return H.json_response(400, nil, "Monitor ID required") end
        db.remove_status_page_monitor(id, monitor_id)
        return H.deleted()
    end

    if not db.get_status_page(id) then
        return H.json_response(404, nil, "Status page not found")
    end
    db.delete_status_page(id)
    return H.deleted()
end

return M
