local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local notifier = require("lib.notifier")
local logger = require("lib.logger")

function on_finished()
    if not runtime_config.is_central() then return end
    if db.get_int("checker_stale_alert", 0) ~= 1 then return end

    local channel_id = db.get_int("checker_stale_channel_id", 0)
    if channel_id == 0 then return end

    local ch = db.get_channel(channel_id)
    if not ch or ch.enabled ~= 1 then return end

    local now = os.time()
    for _, node in ipairs(db.list_nodes()) do
        if node.active == 1 then
            local minutes = tonumber(node.stale_alert_minutes) or 0
            if minutes > 0 and node.last_seen_at then
                local stale_ok = now - node.last_seen_at >= minutes * 60
                local cool_ok = (not node.stale_alerted_at)
                    or (now - node.stale_alerted_at >= minutes * 60)
                if stale_ok and cool_ok then
                    local mins_ago = math.floor((now - node.last_seen_at) / 60)
                    local alert = {
                        monitor = node.name,
                        severity = "DOWN",
                        message = string.format(
                            'Checker "%s" last contact %dm ago', node.name, mins_ago),
                        url = "",
                        timestamp = now,
                    }
                    local ok, err = notifier.dispatch_to_channel(channel_id, alert)
                    if ok then
                        db.set_node_stale_alerted(node.id, now)
                        logger.info(string.format(
                            'stale alert sent for "%s" after %dm without contact',
                            node.name, mins_ago), "checker.stale")
                    else
                        logger.warn("stale alert dispatch failed: "
                            .. logger.err_msg(err), "checker.stale")
                    end
                end
            end
        end
    end
end
