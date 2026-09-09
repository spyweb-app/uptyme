local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local check_buffer = require("lib.check_buffer")
local report_buffer = require("lib.report_buffer")
local central = require("lib.central_client")
local logger = require("lib.logger")
local consensus = require("lib.consensus")

local role = runtime_config.role()

function on_finished()
    local now = os.time()

    local ok, err = pcall(function()
        db.update_monitor_status_batch(check_buffer.drain_status())
        db.insert_check_history_batch(check_buffer.drain_history())

        if role == "central" then
            local reports = check_buffer.drain_node_reports()
            db.upsert_node_reports_batch(reports)
            for _, report in ipairs(reports) do
                consensus.evaluate(report.monitor_id, report.is_up)
            end
        end
    end)
    if not ok then
        logger.error("local db flush failed: " .. logger.err_msg(err), "db.flush")
    end

    local reports = report_buffer.flush()
    if #reports > 0 then
        local _, err = central.post("/report", { reports = reports })
        if err then
            logger.error("batch report failed: " .. logger.err_msg(err), "report.flush")
        end
    end

    local last = tonumber(store_get("last_cleanup")) or 0
    if now - last >= 86400 then
        store_set("last_cleanup", tostring(now))

        local days = db.get_int("retention_days", 90)
        local deleted = db.cleanup_old_history(days)
        if deleted and deleted > 0 then
            logger.info("cleaned " .. deleted .. " records older than " .. days .. " days", "cleanup")
        end
        db.cleanup_old_transitions(days)
    end
end
