local M = {}

-- Fixed-window limiter with two persistent keys per scope/identity pair.
-- SpyWeb global storage has no TTL or key enumeration, so avoid creating a
-- new key for every window.
function M.check(key, limit, window_sec)
    local now = os.time()
    local start_key = "ratelimit:" .. key .. ":start"
    local count_key = "ratelimit:" .. key .. ":count"

    local window_start = tonumber(global_store_get(start_key) or "0") or 0
    if now - window_start >= window_sec then
        global_store_set(start_key, tostring(now))
        global_store_set(count_key, "0")
        window_start = now
    end

    local count = global_store_incr(count_key, 0, 1)
    if count > limit then
        local retry_after = window_start + window_sec - now
        if retry_after < 1 then retry_after = 1 end
        return {
            retry_after = retry_after,
            limit = limit,
            remaining = 0,
        }
    end

    return nil
end

return M
