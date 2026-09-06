local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")

local M = {}

local function reject_checker_mutation()
    if runtime_config.is_checker() then
        return H.json_response(403, nil, "Status pages are managed on the central node")
    end
end

local function body(self)
    local data = json_decode(self.body or "")
    if not data or type(data) ~= "table" then
        return nil, H.json_response(400, nil, "Invalid JSON body")
    end
    return data
end

local function page_id(self)
    return tonumber(self.path_args[1])
end

function M.list(self)
    if self.path_args[1] then
        local id = page_id(self)
        if not id then return H.json_response(400, nil, "Status page ID required") end
        if self.path_args[2] == "monitors" then
            if not db.get_status_page(id) then return H.json_response(404, nil, "Status page not found") end
            return H.json_response(200, db.list_status_page_monitors(id))
        end
        return H.json_response(200, db.get_status_page(id))
    end
    return H.json_response(200, db.list_status_pages())
end

function M.create(self)
    local denied = reject_checker_mutation()
    if denied then return denied end
    local data, err_response = body(self)
    if not data then return err_response end

    if self.path_args[1] and self.path_args[2] == "monitors" then
        local id = page_id(self)
        local membership, err = db.add_status_page_monitor(id, data.monitor_id, data.display_order)
        if not membership then
            local code = (err == "status page not found" or err == "monitor not found") and 404 or 400
            return H.json_response(code, nil, err)
        end
        return H.json_response(201, membership)
    end

    local row, err = db.create_status_page(data)
    if not row then
        return H.json_response(err == "monitor not found" and 404 or 400, nil, err)
    end
    return H.json_response(201, row)
end

function M.update(self)
    local denied = reject_checker_mutation()
    if denied then return denied end
    local id = page_id(self)
    if not id then return H.json_response(400, nil, "Status page ID required") end

    if self.path_args[2] == "monitors" then
        local monitor_id = tonumber(self.path_args[3])
        if not monitor_id then return H.json_response(400, nil, "Monitor ID required") end
        local data, err_response = body(self)
        if not data then return err_response end
        local row, err = db.update_status_page_monitor_order(id, monitor_id, data.display_order)
        if not row then return H.json_response(404, nil, err or "Membership not found") end
        return H.json_response(200, row)
    end

    local data, err_response = body(self)
    if not data then return err_response end
    local row, err = db.update_status_page(id, data)
    if not row then return H.json_response(404, nil, err) end
    return H.json_response(200, row)
end

function M.remove(self)
    local denied = reject_checker_mutation()
    if denied then return denied end
    local id = page_id(self)
    if not id then return H.json_response(400, nil, "Status page ID required") end

    if self.path_args[2] == "monitors" then
        local monitor_id = tonumber(self.path_args[3])
        if not monitor_id then return H.json_response(400, nil, "Monitor ID required") end
        db.remove_status_page_monitor(id, monitor_id)
        return H.json_response(200, { deleted = true })
    end

    if not db.get_status_page(id) then return H.json_response(404, nil, "Status page not found") end
    db.delete_status_page(id)
    return H.json_response(200, { deleted = true })
end

return M
