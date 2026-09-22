local H = require("server.tests.helpers")
local db = require("lib.db")

function test_get_channels_empty()
    db_exec("DELETE FROM notification_channels")
    local resp = http_get(H.api("/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_empty_channels_returns_json_array()
    db_exec("DELETE FROM notification_channels")
    local resp = http_get(H.api("/channels"))
    spyweb.assert_eq(resp.status, 200)
    spyweb.assert_ne(string.find(resp.body, '"data":%[%]'), nil)
end

function test_create_channel()
    db_exec("DELETE FROM notification_channels")
    local resp = http_post(H.api("/channels"), json_encode({ name = "Webhook", type = "webhook", config = '{"url":"https://hook.example.com"}' }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 201)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "Webhook")
    spyweb.assert_eq(body.data.type, "webhook")
end

function test_create_channel_missing_name()
    local resp = http_post(H.api("/channels"), json_encode({ type = "webhook" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 400)
end

function test_get_channels()
    db_exec("DELETE FROM notification_channels")
    http_post(H.api("/channels"), json_encode({ name = "Chan", type = "webhook", config = '{"url":"https://c.com"}' }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 1)
    spyweb.assert_eq(body.data[1].name, "Chan")
end

function test_update_channel()
    db_exec("DELETE FROM notification_channels")
    local create = json_decode(http_post(H.api("/channels"), json_encode({ name = "OldChan", type = "webhook", config = '{"url":"https://old.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "PUT", url = H.api("/channels/" .. id), body = json_encode({ name = "NewChan" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "NewChan")
end

function test_delete_channel()
    db_exec("DELETE FROM notification_channels")
    local create = json_decode(http_post(H.api("/channels"), json_encode({ name = "DelChan", type = "webhook", config = '{"url":"https://d.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "DELETE", url = H.api("/channels/" .. id) })
    spyweb.assert_eq(resp.status, 200)
    local list = json_decode(http_get(H.api("/channels")).body)
    spyweb.assert_eq(#list.data, 0)
end

function test_delete_channel_404()
    local resp = http_request({ method = "DELETE", url = H.api("/channels/999999") })
    spyweb.assert_eq(resp.status, 404)
end

function test_channel_test_404()
    local resp = http_request({ method = "PUT", url = H.api("/channels/999999/test"), body = "", headers = {} })
    spyweb.assert_eq(resp.status, 404)
end

