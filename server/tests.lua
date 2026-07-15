local import_export = require("lib.import_export")
local db = require("lib.db")
db.ensure_schema()

-- =============================================================================
-- Import / Export — pure logic
-- =============================================================================

function test_csv_escape()
    spyweb.assert_eq(import_export.csv_escape("hello"), "hello")
    spyweb.assert_eq(import_export.csv_escape("he,llo"), '"he,llo"')
    spyweb.assert_eq(import_export.csv_escape('he"llo'), '"he""llo"')
end

function test_parse_csv_row()
    local r = import_export.parse_csv_row("a,b,c")
    spyweb.assert_eq(r[1], "a")
    spyweb.assert_eq(r[2], "b")
    spyweb.assert_eq(r[3], "c")
end

function test_parse_csv_row_quoted()
    local r = import_export.parse_csv_row('"he,llo","wo""rld"')
    spyweb.assert_eq(r[1], "he,llo")
    spyweb.assert_eq(r[2], 'wo"rld')
end

function test_parse_csv()
    local csv = "name,url,method\nTest,https://test.com,GET\nFoo,https://foo.com,HEAD"
    local rows = import_export.parse_csv(csv)
    spyweb.assert_eq(#rows, 2)
    spyweb.assert_eq(rows[1].name, "Test")
    spyweb.assert_eq(rows[1].url, "https://test.com")
    spyweb.assert_eq(rows[1].method, "GET")
end

function test_parse_csv_missing_header()
    local r = import_export.parse_csv("foo,bar\na,b")
    spyweb.assert_eq(r, nil)
end

function test_parse_csv_too_short()
    local r = import_export.parse_csv("name,url")
    spyweb.assert_eq(r, nil)
end

function test_parse_import_json()
    local r = import_export.parse_import('[{"name":"T","url":"https://t.com"}]')
    spyweb.assert_eq(#r, 1)
    spyweb.assert_eq(r[1].name, "T")
end

function test_parse_import_json_single_object()
    local r = import_export.parse_import('{"name":"T","url":"https://t.com"}')
    spyweb.assert_eq(#r, 1)
    spyweb.assert_eq(r[1].name, "T")
end

function test_parse_import_csv()
    local r = import_export.parse_import("name,url\nT,https://t.com")
    spyweb.assert_eq(#r, 1)
    spyweb.assert_eq(r[1].name, "T")
end

function test_validate_entry()
    spyweb.assert_eq(import_export.validate_entry({ name = "T", url = "https://t.com" }), true)
    spyweb.assert_eq(import_export.validate_entry({ name = "" }), false)
    spyweb.assert_eq(import_export.validate_entry({ name = "T" }), false)
    spyweb.assert_eq(import_export.validate_entry("string"), false)
end

function test_export_csv()
    local row = { name = "Test", url = "https://t.com", method = "HEAD", interval_sec = 300, timeout_ms = 10000, check_value = "", desktop_notify = 0, enabled = 1 }
    local csv = import_export.export_csv({ row })
    spyweb.assert_eq(csv:match("^name,url"), "name,url")
    spyweb.assert_eq(csv:match("Test,https://t%.com,HEAD"), "Test,https://t.com,HEAD")
end

-- =============================================================================
-- Integration — HTTP endpoints
-- =============================================================================

local function api(path)
    return "http://127.0.0.1:" .. SERVER_PORT .. "/api/v" .. path
end

local function public_api(path)
    return "http://127.0.0.1:" .. SERVER_PORT .. "/api/public" .. path
end

function test_get_monitors_empty()
    db_exec("DELETE FROM monitors")
    local resp = http_get(api("/monitors"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 0)
    spyweb.assert_eq(body.data.total, 0)
end

function test_create_monitor()
    db_exec("DELETE FROM monitors")
    local resp = http_post(api("/monitors"), json_encode({ name = "CreateTest", url = "https://create-test.example.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 201)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(body.data.name, "CreateTest")
end

function test_get_monitors()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "Test", url = "https://test.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/monitors"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 1)
    spyweb.assert_eq(body.data.total, 1)
end

function test_create_monitor_missing_name()
    local resp = http_post(api("/monitors"), json_encode({ url = "https://no-name.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 400)
end

function test_get_monitor_404()
    local resp = http_get(api("/monitors/999999"))
    spyweb.assert_eq(resp.status, 404)
end

function test_delete_monitor_404()
    local resp = http_request({ method = "DELETE", url = api("/monitors/999999") })
    spyweb.assert_eq(resp.status, 404)
end

function test_update_monitor()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "OldName", url = "https://update.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "PUT", url = api("/monitors/" .. id), body = json_encode({ name = "NewName" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "NewName")
end

function test_delete_monitor()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "DeleteMe", url = "https://delete.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "DELETE", url = api("/monitors/" .. id) })
    spyweb.assert_eq(resp.status, 200)
    local get = http_get(api("/monitors/" .. id))
    spyweb.assert_eq(get.status, 404)
end

function test_get_monitor_by_id()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "GetTest", url = "https://get-test.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(api("/monitors/" .. id))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "GetTest")
    spyweb.assert_eq(body.data.id, id)
end

function test_get_monitor_history_empty()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "Hist", url = "https://hist.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(api("/monitors/" .. id .. "/history"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_get_monitor_summary()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "Summary", url = "https://summary.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(api("/monitors/" .. id .. "/summary"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_get_monitor_channels()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(api("/monitors"), json_encode({ name = "ChanMon", url = "https://chanmon.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(api("/monitors/" .. id .. "/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_create_monitor_duplicate_url()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "First", url = "https://dup.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_post(api("/monitors"), json_encode({ name = "Second", url = "https://dup.example.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 409)
end

function test_update_monitor_channels()
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM notification_channels")
    local mon = json_decode(http_post(api("/monitors"), json_encode({ name = "ChanMon2", url = "https://chanmon2.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local ch = json_decode(http_post(api("/channels"), json_encode({ name = "ChanForMon", type = "webhook", config = '{"url":"https://h.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local mid = mon.data.id
    local cid = ch.data.id
    local resp = http_request({ method = "PUT", url = api("/monitors/" .. mid .. "/channels"), body = json_encode({ cid }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local get = json_decode(http_get(api("/monitors/" .. mid .. "/channels")).body)
    spyweb.assert_eq(#get.data, 1)
    spyweb.assert_eq(get.data[1], cid)
end

function test_get_monitors_paginated()
    db_exec("DELETE FROM monitors")
    for i = 1, 30 do
        local name = "P" .. i
        http_post(api("/monitors"), json_encode({ name = name, url = "https://p" .. i .. ".example.com" }), { ["Content-Type"] = "application/json" })
    end
    local resp = http_get(api("/monitors?page=2&per_page=10"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 10)
    spyweb.assert_eq(body.data.total, 30)
    spyweb.assert_eq(body.data.page, 2)
    spyweb.assert_eq(body.data.per_page, 10)
    spyweb.assert_eq(body.data.total_pages, 3)
end

function test_get_monitors_search()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "Alpha", url = "https://alpha.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(api("/monitors"), json_encode({ name = "Beta", url = "https://beta.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/monitors?q=alpha"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 1)
    spyweb.assert_eq(body.data.items[1].name, "Alpha")
end

function test_get_monitors_sort()
    db_exec("DELETE FROM monitors")
    local names = { "Charlie", "Alpha", "Bravo" }
    for _, name in ipairs(names) do
        http_post(api("/monitors"), json_encode({ name = name, url = "https://" .. name .. ".example.com" }), { ["Content-Type"] = "application/json" })
    end
    local resp = http_get(api("/monitors?sort=name&order=desc"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 3)
    spyweb.assert_eq(body.data.items[1].name, "Charlie")
    spyweb.assert_eq(body.data.items[3].name, "Alpha")
end

function test_get_monitors_enabled_filter()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "EnabledMon", url = "https://enabled.example.com", enabled = 1 }), { ["Content-Type"] = "application/json" })
    http_post(api("/monitors"), json_encode({ name = "DisabledMon", url = "https://disabled.example.com", enabled = 0 }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/monitors?enabled=0"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 1)
    spyweb.assert_eq(body.data.items[1].name, "DisabledMon")
end

function test_import_json()
    db_exec("DELETE FROM monitors")
    local json = '[{"name":"JSON Import","url":"https://json-import.example.com"}]'
    local resp = http_post(api("/monitors_import"), json, { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.imported, 1)
    spyweb.assert_eq(body.data.failed, 0)
end

function test_import_csv()
    db_exec("DELETE FROM monitors")
    local csv = "name,url,method,interval_sec\nCSV Import,https://csv-import.example.com,HEAD,60"
    local resp = http_post(api("/monitors_import"), csv, { ["Content-Type"] = "text/csv" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.imported, 1)
    spyweb.assert_eq(body.data.skipped, 0)
    spyweb.assert_eq(body.data.failed, 0)
end

function test_import_bad_format()
    local resp = http_post(api("/monitors_import"), "garbage data here", { ["Content-Type"] = "text/plain" })
    spyweb.assert_eq(resp.status, 400)
end

function test_export_json()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "ExportJSON", url = "https://export-json.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/monitors_export"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data, 1)
    spyweb.assert_eq(body.data[1].name, "ExportJSON")
end

function test_export_csv()
    db_exec("DELETE FROM monitors")
    http_post(api("/monitors"), json_encode({ name = "ExportCSV", url = "https://export-csv.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/monitors_export?format=csv"))
    spyweb.assert_eq(resp.status, 200)
    local ct = resp.headers["Content-Type"] or resp.headers["content-type"] or ""
    spyweb.assert_eq(ct, "text/csv")
end

function test_get_settings()
    local resp = http_get(api("/settings"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.retention_days, "90")
    spyweb.assert_eq(body.data.alert_cooldown_sec, "300")
end

function test_update_settings()
    local resp = http_request({ method = "PUT", url = api("/settings"), body = json_encode({ retention_days = "30" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.retention_days, "30")
end

function test_get_channels_empty()
    db_exec("DELETE FROM notification_channels")
    local resp = http_get(api("/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_create_channel()
    db_exec("DELETE FROM notification_channels")
    local resp = http_post(api("/channels"), json_encode({ name = "Webhook", type = "webhook", config = '{"url":"https://hook.example.com"}' }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 201)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "Webhook")
    spyweb.assert_eq(body.data.type, "webhook")
end

function test_create_channel_missing_name()
    local resp = http_post(api("/channels"), json_encode({ type = "webhook" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 400)
end

function test_get_channels()
    db_exec("DELETE FROM notification_channels")
    http_post(api("/channels"), json_encode({ name = "Chan", type = "webhook", config = '{"url":"https://c.com"}' }), { ["Content-Type"] = "application/json" })
    local resp = http_get(api("/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 1)
    spyweb.assert_eq(body.data[1].name, "Chan")
end

function test_update_channel()
    db_exec("DELETE FROM notification_channels")
    local create = json_decode(http_post(api("/channels"), json_encode({ name = "OldChan", type = "webhook", config = '{"url":"https://old.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "PUT", url = api("/channels/" .. id), body = json_encode({ name = "NewChan" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "NewChan")
end

function test_delete_channel()
    db_exec("DELETE FROM notification_channels")
    local create = json_decode(http_post(api("/channels"), json_encode({ name = "DelChan", type = "webhook", config = '{"url":"https://d.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "DELETE", url = api("/channels/" .. id) })
    spyweb.assert_eq(resp.status, 200)
    local list = json_decode(http_get(api("/channels")).body)
    spyweb.assert_eq(#list.data, 0)
end

function test_delete_channel_404()
    local resp = http_request({ method = "DELETE", url = api("/channels/999999") })
    spyweb.assert_eq(resp.status, 404)
end

function test_channel_test_404()
    local resp = http_request({ method = "PUT", url = api("/channels/999999/test"), body = "", headers = {} })
    spyweb.assert_eq(resp.status, 404)
end

function test_health()
    local resp = http_get(api("/health"))
    spyweb.assert_eq(resp.status, 200)
end

-- =============================================================================
-- Cluster bootstrap / auth
-- =============================================================================

function test_cluster_version_requires_auth()
    local resp = http_get(public_api("/cluster_version"))
    spyweb.assert_eq(resp.status, 401)
end

function test_cluster_version_and_export()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    local node = db.create_node({ name = "Checker One", role = "checker", token = "node1.secret" })
    spyweb.assert_ne(node, nil)

    local before_version = db.get_monitors_version()
    http_post(api("/monitors"), json_encode({ name = "ClusterMon", url = "https://cluster.example.com" }), { ["Content-Type"] = "application/json" })
    local after_version = db.get_monitors_version()
    spyweb.assert_eq(after_version, before_version + 1)

    local headers = { ["X-Pulse-Checker-Token"] = "node1.secret" }
    local version_resp = http_get(public_api("/cluster_version"), headers)
    spyweb.assert_eq(version_resp.status, 200)
    spyweb.assert_eq(tonumber(version_resp.body), after_version)

    local export_resp = http_get(public_api("/cluster_export"), headers)
    spyweb.assert_eq(export_resp.status, 200)
    local export_body = json_decode(export_resp.body)
    spyweb.assert_eq(export_body.success, true)
    spyweb.assert_eq(#export_body.data, 1)
    spyweb.assert_eq(export_body.data[1].name, "ClusterMon")
    spyweb.assert_eq(export_body.data[1].url, "https://cluster.example.com")
end
