local runtime_config = require("lib.runtime_config")

local M = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, none = 5 }

local throttle_counts = {}

local function get_config()
    return runtime_config.logging()
end

local function emit(level_num, msg, category)
    local cfg = get_config()
    local configured = LEVELS[cfg.level or "error"]
    if not configured then configured = LEVELS.error end
    if level_num < configured then return end

    local output = cfg.output or "file"
    if output == "none" then return end

    local extra = 0
    if category then
        local limit = cfg.throttle
        if limit and limit > 0 then
            local n = (throttle_counts[category] or 0) + 1
            throttle_counts[category] = n
            if n > 1 and n <= limit + 1 then return end
            if n > limit + 1 then
                extra = n - 2
                throttle_counts[category] = 1
            end
        end
    end

    if extra > 0 then
        msg = msg .. " (" .. extra .. " suppressed)"
    end

    if output == "file" or output == "both" then
        log(msg)
    end
    if output == "terminal" or output == "both" then
        print(msg)
    end
end

function M.debug(msg, category)
    emit(1, msg, category)
end

function M.info(msg, category)
    emit(2, msg, category)
end

function M.warn(msg, category)
    emit(3, msg, category)
end

function M.error(msg, category)
    emit(4, msg, category)
end

function M._reset()
    throttle_counts = {}
end

function M.err_msg(err)
    if type(err) == "string" then return err end
    if type(err) == "table" then
        return tostring(err.message or err.error or dump(err))
    end
    return tostring(err)
end

return M
