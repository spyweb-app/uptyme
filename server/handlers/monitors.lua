local H = require("helpers")
local db = require("lib.db")
local import_export = require("lib.import_export")
local validate = require("lib.validate")

local M = {}

function M.export(self)
    local fmt = self.query.format or "json"
    local rows = db.export_all()
    if fmt == "csv" then
        return {
            status = 200,
            body = import_export.export_csv(rows),
            headers = {
                ["Content-Type"] = "text/csv",
                ["Content-Disposition"] = 'attachment; filename="uptyme-monitors.csv"',
            },
        }
    end
    return H.json_response(200, rows)
end

function M.import(self)
    local denied = H.reject_checker_mutation("Monitors")
    if denied then return denied end

    local entries = import_export.parse_import(self.body or "")
    if not entries then
        return H.json_response(400, nil, "Invalid JSON or CSV — check the file format and try again")
    end
    local imported, skipped, failed = 0, 0, 0
    for _, entry in ipairs(entries) do
        if not import_export.validate_entry(entry) then
            failed = failed + 1
        else
            local ok, _ = db.insert_monitor(entry)
            if ok then
                imported = imported + 1
            else
                skipped = skipped + 1
            end
        end
    end
    if imported > 0 then
        db.bump_monitors_version()
    end
    return H.json_response(200, {
        imported = imported, skipped = skipped, failed = failed, total = #entries,
    })
end

function M.list(self)
    local cmd = self.path_args[1]
    local id = tonumber(cmd)

    if id then
        local sub = self.query.view

        if sub == "history" then
            local before = H.int_param(self.query, "before", os.time())
            local limit = H.int_param(self.query, "limit", 50)
            local rows = db.get_history(id, before, limit)
            return H.json_response(200, rows)
        end

        if sub == "summary" then
            local days = H.int_param(self.query, "days", 7)
            local group = H.str_param(self.query, "group", "day")
            local rows = db.get_summary(id, days, group)
            return H.json_response(200, rows)
        end

        if sub == "channels" then
            return H.json_response(200, db.get_monitor_channel_ids(id))
        end

        local row = db.get(id)
        if not row then
            return H.json_response(404, nil, "Monitor not found")
        end
        return H.json_response(200, row)
    end

    local opts = {
        page = H.int_param(self.query, "page", 1),
        per_page = H.int_param(self.query, "per_page", 25),
        sort = self.query.sort or "name",
        order = self.query.order or "asc",
        q = self.query.q or "",
    }
    if self.query.enabled ~= nil then
        opts.enabled = H.int_param(self.query, "enabled")
    end
    local result = db.monitor_list(opts)
    return H.json_response(200, result)
end

function M.create(self)
    local denied = H.reject_checker_mutation("Monitors")
    if denied then return denied end

    local data, err = H.parse_body(self)
    if not data then return err end

    local validated, val_err = H.validate_or_400(data, validate.monitor_create)
    if not validated then return val_err end

    if db.get_by_url(validated.url) then
        return H.json_response(409, nil, "A monitor with this URL already exists")
    end

    local ok, db_err = db.insert_monitor(validated)
    if not ok then
        return H.json_response(409, nil, "Failed to create: " .. tostring(db_err))
    end
    db.bump_monitors_version()

    local row = db.get_by_url(validated.url)
    return H.json_response(201, row)
end

function M.update(self)
    local denied = H.reject_checker_mutation("Monitors")
    if denied then return denied end

    local id, id_err = H.require_id(self, "Monitor")
    if not id then return id_err end

    local data, parse_err = H.parse_body(self)
    if not data then return parse_err end

    local channel_ids = data.channel_ids
    if channel_ids ~= nil then
        if type(channel_ids) ~= "table" then
            return H.json_response(400, nil, "channel_ids must be an array of positive integers")
        end
        for i, cid in ipairs(channel_ids) do
            if type(cid) ~= "number" or cid ~= math.floor(cid) or cid < 1 then
                return H.json_response(400, nil, "channel_ids[" .. i .. "] must be a positive integer")
            end
        end
    end

    local validated, val_err = H.validate_or_400(data, validate.monitor_update)
    if not validated then return val_err end

    local updatable = { "name", "url", "method", "interval_sec", "timeout_ms", "check_value", "enabled", "desktop_notify", "check_cert", "cert_threshold_days" }
    local updated, update_err = db.update_by_id("monitors", id, validated, updatable, { updated_at = true })

    if updated then
        db.bump_monitors_version()
    elseif channel_ids == nil then
        return H.json_response(400, nil, update_err or "No fields to update")
    end

    if channel_ids ~= nil then
        db.set_monitor_channels(id, channel_ids)
    end

    local row = db.get(id)
    if not row then
        return H.json_response(404, nil, "Monitor not found")
    end
    return H.json_response(200, row)
end

function M.remove(self)
    local denied = H.reject_checker_mutation("Monitors")
    if denied then return denied end

    local id, id_err = H.require_id(self, "Monitor")
    if not id then return id_err end

    local row, row_err = H.find_or_404(db.get, id, "Monitor")
    if not row then return row_err end

    db.delete_monitor(id)
    db.bump_monitors_version()
    return H.deleted()
end

return M
