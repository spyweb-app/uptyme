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
