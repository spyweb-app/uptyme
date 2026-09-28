local db = require("lib.db")
local logger = require("lib.logger")

-- stylua: ignore
local services = {
    webhook = require("lib.notifier.webhook"),
    discord = require("lib.notifier.discord"),
    slack   = require("lib.notifier.slack"),
    ntfy    = require("lib.notifier.ntfy"),
    email   = require("lib.notifier.email"),
}

function dispatch(monitor_id, alert)
    local channels = db.get_alert_channels(monitor_id)
    for _, ch in ipairs(channels) do
        local cfg = json_decode(ch.config) or {}
        local svc = services[ch.type]
        if svc then
            local ok, resp, err = pcall(svc.send, cfg, alert)
            if not ok then
                logger.warn("channel " .. ch.id .. " (" .. ch.type .. ") failed: " .. logger.err_msg(resp), "channel.send")
            elseif resp == nil then
                logger.warn("channel " .. ch.id .. " (" .. ch.type .. ") failed: " .. logger.err_msg(err or "no response"), "channel.send")
            elseif type(resp) == "table" and resp.status and resp.status >= 400 then
                logger.warn("channel " .. ch.id .. " (" .. ch.type .. ") failed: HTTP " .. resp.status, "channel.send")
            end
        end
    end
end

function dispatch_to_channel(channel_id, alert)
    local ch = db.get_channel(channel_id)
    if not ch then return nil, "Channel not found" end
    local cfg = json_decode(ch.config) or {}
    local svc = services[ch.type]
    if not svc then return nil, "Unknown channel type: " .. ch.type end
    local ok, resp, err = pcall(svc.send, cfg, alert)
    if not ok then return nil, tostring(resp) end
    if resp == nil then return nil, logger.err_msg(err or "channel returned no response") end
    return true, resp
end

function dispatch_config(channels, alert)
    for _, ch in ipairs(channels or {}) do
        local cfg = type(ch.config) == "string" and (json_decode(ch.config) or {}) or (ch.config or {})
        local svc = services[ch.type]
        if svc then
            local ok, resp, err = pcall(svc.send, cfg, alert)
            if not ok then
                logger.warn("channel (" .. ch.type .. ") failed: " .. logger.err_msg(resp), "channel.send")
            elseif resp == nil then
                logger.warn("channel (" .. ch.type .. ") failed: " .. logger.err_msg(err or "no response"), "channel.send")
            elseif type(resp) == "table" and resp.status and resp.status >= 400 then
                logger.warn("channel (" .. ch.type .. ") failed: HTTP " .. resp.status, "channel.send")
            end
        end
    end
end

return { dispatch = dispatch, dispatch_to_channel = dispatch_to_channel, dispatch_config = dispatch_config }
