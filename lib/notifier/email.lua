local M = {}

function M.send(cfg, alert)
    local provider = cfg.provider or "sendgrid"
    if provider ~= "sendgrid" then
        return nil, "unsupported email provider: " .. tostring(provider)
    end
    return http_post("https://api.sendgrid.com/v3/mail/send", json_encode({
        personalizations = {{ to = {{ email = cfg.to }}}},
        from = { email = cfg.from },
        subject = "[" .. (cfg.instance_name or "UPTYME") .. "] " .. alert.severity .. ": " .. alert.monitor,
        content = {{ type = "text/plain", value = alert.message .. "\n\n" .. alert.url }},
    }), {
        ["Authorization"] = "Bearer " .. cfg.api_key,
        ["Content-Type"] = "application/json",
    })
end

return M
