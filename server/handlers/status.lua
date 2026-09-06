local H = require("helpers")
local db = require("lib.db")
local runtime_config = require("lib.runtime_config")

local M = {}

function M.get(self)
    -- A checker only receives authenticated cluster endpoints. Public pages
    -- are served by the standalone or central HTTP server.
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

    local result
    if page.type == "monitor" then
        result = db.get_public_monitor_status(page.id)
    elseif page.type == "group" then
        result = db.get_public_group_status(page.id)
    end

    -- Keep the route safe if a page is deleted or becomes invalid between
    -- lookup and status loading.
    if not result then
        return H.json_response(404, nil, "Not found")
    end

    return H.json_response(200, result)
end

return M
