local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local settings = require("lib.db.settings")

local M = {}

function M.get(self)
    if runtime_config.is_checker() then
        return H.json_response(404, nil, "Not found")
    end

    local slug = self.path_args and self.path_args[1]
    if not slug or slug == "" then
        return H.json_response(404, nil, "Not found")
    end

    local page = db.get_status_page_by_slug(slug)
    if not page or page.is_public ~= 1 then
        return H.json_response(404, nil, "Not found")
    end

    if self.path_args[2] == "report" then
        local raw_days = self.query and self.query.days
        local days
        if raw_days ~= nil then days = tonumber(raw_days) or false end
        local raw_monitor_id = self.query and self.query.monitor_id
        local monitor_id = raw_monitor_id == nil and nil or tonumber(raw_monitor_id)
        if raw_monitor_id ~= nil and not monitor_id then
            return H.json_response(400, nil, "Invalid monitor_id")
        end
        local opts = {
            month = self.query and self.query.month,
            days = days,
            group = self.query and self.query.group,
        }
        local result, err = db.get_public_report(slug, opts, monitor_id)
        if not result then
            if err == "Invalid month" or err == "Invalid days" or err == "Invalid group"
                or err == "month and days cannot be combined" then
                return H.json_response(400, nil, err)
            end
            return H.json_response(404, nil, "Not found")
        end
        return H.json_response(200, result)
    end

    local month = self.query and self.query.month
    local days = tonumber(self.query and self.query.days) or 30
    local group = self.query and self.query.group or "day"

    local result
    if page.type == "monitor" then
        result = db.get_public_monitor_status(page.id, month, days, group)
    elseif page.type == "group" then
        result = db.get_public_group_status(page.id, month)
    end

    if not result then
        return H.json_response(404, nil, "Not found")
    end

    result.theme = settings.get_setting("status_page_theme", "light")
    result.instance_name = settings.get_setting("instance_name", "UPTYME")

    return H.json_response(200, result)
end

return M
