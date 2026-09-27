local H = require("server.tests.helpers")
local db = require("lib.db")

function test_create_node_role_ignored()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local resp = http_post(H.api("/nodes"), json_encode({ name = "TestNode", role = "central" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 201)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.node.name, "TestNode")
    spyweb.assert_eq(body.data.node.role, "checker") -- should default to checker, not central
end

function test_update_node_valid()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local create = json_decode(http_post(H.api("/nodes"), json_encode({ name = "OldNode" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.node.id
    local resp = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ name = "NewNode", role = "admin" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "NewNode")
    spyweb.assert_eq(body.data.role, "checker") -- role shouldn't change
end

function test_create_node_missing_name()
    local resp = http_post(H.api("/nodes"), json_encode({}), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 400)
end

function test_update_node_stale_alert_minutes_persists()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local create = json_decode(http_post(H.api("/nodes"), json_encode({ name = "StaleNode" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.node.id

    local resp = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ stale_alert_minutes = 15 }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.stale_alert_minutes, 15)

    local list = json_decode(http_get(H.api("/nodes")).body)
    local found
    for _, n in ipairs(list.data) do
        if n.id == id then found = n end
    end
    spyweb.assert_ne(found, nil)
    spyweb.assert_eq(found.stale_alert_minutes, 15)
end

function test_update_node_stale_alert_minutes_range()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local create = json_decode(http_post(H.api("/nodes"), json_encode({ name = "RangeNode" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.node.id

    local too_high = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ stale_alert_minutes = 10081 }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(too_high.status, 400)

    local negative = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ stale_alert_minutes = -1 }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(negative.status, 400)

    local saved = db.get_node(id)
    spyweb.assert_eq(saved.stale_alert_minutes, 0)
end

function test_update_node_stale_alert_minutes_accepts_string_number()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local create = json_decode(http_post(H.api("/nodes"), json_encode({ name = "StrNode" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.node.id

    local resp = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ stale_alert_minutes = "30" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    spyweb.assert_eq(db.get_node(id).stale_alert_minutes, 30)
end

function test_update_node_active()
    db_exec("DELETE FROM nodes WHERE role != 'central'")
    local create = json_decode(http_post(H.api("/nodes"), json_encode({ name = "ActiveNode" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.node.id
    spyweb.assert_eq(create.data.node.active, 1)

    local off = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ active = 0 }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(off.status, 200)
    spyweb.assert_eq(json_decode(off.body).data.active, 0)

    local on = http_request({ method = "PUT", url = H.api("/nodes/" .. id), body = json_encode({ active = 1 }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(on.status, 200)
    spyweb.assert_eq(json_decode(on.body).data.active, 1)
end
