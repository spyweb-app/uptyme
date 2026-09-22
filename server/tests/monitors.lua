local import_export = require("lib.import_export")
local db = require("lib.db")
local H = require("server.tests.helpers")

local function clear_monitor_create_throttle()
    global_store_delete("ratelimit:admin:monitors:create:127.0.0.1:start")
    global_store_delete("ratelimit:admin:monitors:create:127.0.0.1:count")
end

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

function test_get_monitors_empty()
    db_exec("DELETE FROM monitors")
    local resp = http_get(H.api("/monitors"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 0)
    spyweb.assert_eq(body.data.total, 0)
end

function test_create_monitor()
    db_exec("DELETE FROM monitors")
    local resp = http_post(H.api("/monitors"), json_encode({ name = "CreateTest", url = "https://create-test.example.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 201)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(body.data.name, "CreateTest")
end

function test_get_monitors()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "Test", url = "https://test.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/monitors"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 1)
    spyweb.assert_eq(body.data.total, 1)
end

function test_create_monitor_missing_name()
    local resp = http_post(H.api("/monitors"), json_encode({ url = "https://no-name.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 400)
end

function test_get_monitor_404()
    local resp = http_get(H.api("/monitors/999999"))
    spyweb.assert_eq(resp.status, 404)
end

function test_delete_monitor_404()
    local resp = http_request({ method = "DELETE", url = H.api("/monitors/999999") })
    spyweb.assert_eq(resp.status, 404)
end

function test_update_monitor()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "OldName", url = "https://update.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "PUT", url = H.api("/monitors/" .. id), body = json_encode({ name = "NewName" }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "NewName")
end

function test_delete_monitor()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "DeleteMe", url = "https://delete.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_request({ method = "DELETE", url = H.api("/monitors/" .. id) })
    spyweb.assert_eq(resp.status, 200)
    local get = http_get(H.api("/monitors/" .. id))
    spyweb.assert_eq(get.status, 404)
end

function test_delete_monitor_cleans_dependent_rows()
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM check_history")
    db_exec("DELETE FROM monitor_notifications")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR IGNORE INTO notification_channels (id, name, type, config) VALUES (1, 'c', 'webhook', '{}')")
    db_exec("INSERT OR IGNORE INTO nodes (id, name, role, token_prefix, token_hash) VALUES (1, 'n', 'central', 'x', 'h')")

    local m = db_query("INSERT INTO monitors (name, url) VALUES ('Dep', 'https://dep.example.com') RETURNING id")[1]
    local mid = m.id

    db_exec("INSERT INTO check_history (monitor_id, is_up) VALUES (?, 1)", { mid })
    db_exec("INSERT INTO monitor_notifications (monitor_id, channel_id) VALUES (?, 1)", { mid })
    db_exec("INSERT INTO node_reports (monitor_id, node_id, is_up, reported_at) VALUES (?, 1, 1, ?)", { mid, os.time() })

    db.delete_monitor(mid)

    spyweb.assert_eq(db_query("SELECT COUNT(*) AS c FROM check_history WHERE monitor_id = ?", { mid })[1].c, 0)
    spyweb.assert_eq(db_query("SELECT COUNT(*) AS c FROM monitor_notifications WHERE monitor_id = ?", { mid })[1].c, 0)
    spyweb.assert_eq(db_query("SELECT COUNT(*) AS c FROM node_reports WHERE monitor_id = ?", { mid })[1].c, 0)

    db_exec("DELETE FROM nodes")
end

function test_get_monitor_by_id()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "GetTest", url = "https://get-test.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(H.api("/monitors/" .. id))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.name, "GetTest")
    spyweb.assert_eq(body.data.id, id)
end

function test_get_monitor_history_empty()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "Hist", url = "https://hist.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(H.api("/monitors/" .. id .. "/history"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_get_monitor_summary()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "Summary", url = "https://summary.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(H.api("/monitors/" .. id .. "/summary"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_get_monitor_channels()
    db_exec("DELETE FROM monitors")
    local create = json_decode(http_post(H.api("/monitors"), json_encode({ name = "ChanMon", url = "https://chanmon.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local id = create.data.id
    local resp = http_get(H.api("/monitors/" .. id .. "/channels"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data, 0)
end

function test_create_monitor_duplicate_url()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "First", url = "https://dup.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_post(H.api("/monitors"), json_encode({ name = "Second", url = "https://dup.example.com" }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 409)
end

function test_update_monitor_channels()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM notification_channels")
    local mon = json_decode(http_post(H.api("/monitors"), json_encode({ name = "ChanMon2", url = "https://chanmon2.example.com" }), { ["Content-Type"] = "application/json" }).body)
    local ch = json_decode(http_post(H.api("/channels"), json_encode({ name = "ChanForMon", type = "webhook", config = '{"url":"https://h.com"}' }), { ["Content-Type"] = "application/json" }).body)
    local mid = mon.data.id
    local cid = ch.data.id
    local resp = http_request({ method = "PUT", url = H.api("/monitors/" .. mid .. "/channels"), body = json_encode({ cid }), headers = { ["Content-Type"] = "application/json" } })
    spyweb.assert_eq(resp.status, 200)
    local get = json_decode(http_get(H.api("/monitors/" .. mid .. "/channels")).body)
    spyweb.assert_eq(#get.data, 1)
    spyweb.assert_eq(get.data[1], cid)
end

function test_get_monitors_paginated()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")
    for i = 1, 30 do
        local name = "P" .. i
        http_post(H.api("/monitors"), json_encode({ name = name, url = "https://p" .. i .. ".example.com" }), { ["Content-Type"] = "application/json" })
    end
    local resp = http_get(H.api("/monitors?page=2&per_page=10"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(#body.data.items, 10)
    spyweb.assert_eq(body.data.total, 30)
    spyweb.assert_eq(body.data.page, 2)
    spyweb.assert_eq(body.data.per_page, 10)
    spyweb.assert_eq(body.data.total_pages, 3)
end

function test_get_monitors_search()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "Alpha", url = "https://alpha.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(H.api("/monitors"), json_encode({ name = "Beta", url = "https://beta.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/monitors?q=alpha"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 1)
    spyweb.assert_eq(body.data.items[1].name, "Alpha")
end

function test_get_monitors_sort()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")
    local names = { "Charlie", "Alpha", "Bravo" }
    for _, name in ipairs(names) do
        http_post(H.api("/monitors"), json_encode({ name = name, url = "https://" .. name .. ".example.com" }), { ["Content-Type"] = "application/json" })
    end
    local resp = http_get(H.api("/monitors?sort=name&order=desc"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 3)
    spyweb.assert_eq(body.data.items[1].name, "Charlie")
    spyweb.assert_eq(body.data.items[3].name, "Alpha")
end

function test_get_monitors_enabled_filter()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "EnabledMon", url = "https://enabled.example.com", enabled = 1 }), { ["Content-Type"] = "application/json" })
    http_post(H.api("/monitors"), json_encode({ name = "DisabledMon", url = "https://disabled.example.com", enabled = 0 }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/monitors?enabled=0"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.total, 1)
    spyweb.assert_eq(body.data.items[1].name, "DisabledMon")
end

function test_import_json()
    db_exec("DELETE FROM monitors")
    local json = '[{"name":"JSON Import","url":"https://json-import.example.com"}]'
    local resp = http_post(H.api("/monitors_import"), json, { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.imported, 1)
    spyweb.assert_eq(body.data.failed, 0)
end

function test_import_csv()
    db_exec("DELETE FROM monitors")
    local csv = "name,url,method,interval_sec\nCSV Import,https://csv-import.example.com,HEAD,60"
    local resp = http_post(H.api("/monitors_import"), csv, { ["Content-Type"] = "text/csv" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.data.imported, 1)
    spyweb.assert_eq(body.data.skipped, 0)
    spyweb.assert_eq(body.data.failed, 0)
end

function test_import_bad_format()
    local resp = http_post(H.api("/monitors_import"), "garbage data here", { ["Content-Type"] = "text/plain" })
    spyweb.assert_eq(resp.status, 400)
end

function test_export_json()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "ExportJSON", url = "https://export-json.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/monitors_export"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data, 1)
    spyweb.assert_eq(body.data[1].name, "ExportJSON")
end

function test_export_csv()
    db_exec("DELETE FROM monitors")
    http_post(H.api("/monitors"), json_encode({ name = "ExportCSV", url = "https://export-csv.example.com" }), { ["Content-Type"] = "application/json" })
    local resp = http_get(H.api("/monitors_export?format=csv"))
    spyweb.assert_eq(resp.status, 200)
    local ct = resp.headers["Content-Type"] or resp.headers["content-type"] or ""
    spyweb.assert_eq(ct, "text/csv")
end
