local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local flush = require("lib.flush")
local logger = require("lib.logger")

local role = runtime_config.role()

function on_finished()
    local now = os.time()

    flush.flush("on_finished", now, role)

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
