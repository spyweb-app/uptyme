local H = require("server.tests.helpers")
local db = require("lib.db")

function test_update_settings_valid()
    local resp = http_request({
        method = "PUT",
        url = H.api("/settings"),
        body = json_encode({ retention_days = 30 }),
        headers = { ["Content-Type"] = "application/json" }
    })
    spyweb.assert_eq(resp.status, 200)
end

function test_update_settings_invalid_range()
    local resp = http_request({
        method = "PUT",
        url = H.api("/settings"),
        body = json_encode({ retention_days = 99999 }),
        headers = { ["Content-Type"] = "application/json" }
    })
    spyweb.assert_eq(resp.status, 400)
end

function test_update_settings_invalid_type()
    local resp = http_request({
        method = "PUT",
        url = H.api("/settings"),
        body = json_encode({ treat_4xx_as_down = "not a bool" }),
        headers = { ["Content-Type"] = "application/json" }
    })
    spyweb.assert_eq(resp.status, 400)
end
