local db = require("lib.db")
local check_buffer = require("lib.check_buffer")
local report_buffer = require("lib.report_buffer")
local runtime_config = require("lib.runtime_config")
local consensus = require("lib.consensus")
local central = require("lib.central_client")
local logger = require("lib.logger")

local M = {}

-- Module-local; safe: this job's hooks are execution-locked (sequential
-- within one job). Boots at 0 -> the first check of the very first round
-- flushes solo; the VM persists across rounds while the job is active.
local last_flush = 0

local function should_flush(now)
    local age_ok = (now - last_flush) >= 15 and check_buffer.any_pending()
    local size_ok = check_buffer.total_rows() >= 500
    return age_ok or size_ok
end

function M.maybe_flush(now, role)
    now = now or os.time()
    if not should_flush(now) then return end
    local n = check_buffer.total_rows()
    if n >= 500 then
        -- own category: sharing "db.flush" would let this throttle its errors
        logger.warn("size gate flush: " .. n .. " buffered rows", "db.flush.size")
    end
    M.flush("gate", now, role)
end

-- Order is load-bearing: drains -> local writes -> consume gate -> POST.
-- Drains are swap-based (each row returned exactly once), so a second
-- flush can only ever see empty buffers.
function M.flush(reason, now, role)
    now = now or os.time()
    role = role or runtime_config.role()

    -- 1+2: drains + local persistence + consensus. db_* are async/yielding
    -- bindings; same-job hooks are execution-locked either way. pcall
    -- mirrors what on_finished has always done: log, never raise.
    -- Status/history drains sit outside the pcall: drain can't fail, and
    -- hoisting them keeps the failure counts reportable. Node-report drain
    -- stays inside so an earlier write failure leaves it buffered for retry.
    local status_rows = check_buffer.drain_status()
    local history_rows = check_buffer.drain_history()

    local ok, err = pcall(function()
        db.update_monitor_status_batch(status_rows)
        db.insert_check_history_batch(history_rows)

        if role == "central" then
            local node_reports = check_buffer.drain_node_reports()
            db.upsert_node_reports_batch(node_reports)
            for _, r in ipairs(node_reports) do
                consensus.evaluate(r.monitor_id, r.is_up)
            end
        end
    end)
    if not ok then
        local ctx = ""
        if #status_rows > 0 or #history_rows > 0 then
            ctx = " [drained " .. #status_rows .. " status, " .. #history_rows .. " history]"
        end
        logger.error("local db flush failed (" .. reason .. "): "
            .. logger.err_msg(err) .. ctx, "db.flush")
    end

    -- 3: consume the gate before any further work.
    last_flush = now

    -- 4: report POST — checker only. The load-bearing gate is upstream
    -- (only role == "checker" ever pushes, buffer empty elsewhere), kept
    -- explicit here to mirror the central branch above.
    if role == "checker" then
        local reports = report_buffer.flush()
        if #reports > 0 then
            local _, perr = central.post("/report", { reports = reports })
            if perr then
                logger.error("batch report failed (" .. reason .. "): "
                    .. logger.err_msg(perr), "report.flush")
            end
        end
    end
end

function M._set_last_flush(t)
    last_flush = t
end

return M
