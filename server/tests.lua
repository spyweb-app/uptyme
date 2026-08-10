local import_export = require("lib.import_export")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")
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

function test_settings_get_setting_and_get_int()
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '0')")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('retention_days', '90')")
    spyweb.assert_eq(db.get_setting("instance_name"), "PULSE")
    spyweb.assert_eq(db.get_setting("no_such_key", "fallback"), "fallback")
    spyweb.assert_eq(db.get_int("treat_4xx_as_down", 9), 0)
    spyweb.assert_eq(db.get_int("retention_days", 9), 90)
    spyweb.assert_eq(db.get_int("no_such_key", 5), 5)
    spyweb.assert_eq(db.get_int("instance_name", 5), 5)
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
-- Report / Consensus
-- =============================================================================

function test_report_requires_auth()
    db_exec("DELETE FROM nodes")
    local resp = http_post(public_api("/report"), json_encode({ reports = { { monitor_id = 1, is_up = 1 } } }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 401)
end

function test_report_bad_monitor()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    local nprefix, nsecret = cluster_auth.parse_token("check1.secret")
    local node = db.create_node({ name = "Checker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)
    local headers = { ["Content-Type"] = "application/json", [cluster_auth.HEADER_KEY] = "check1.secret" }
    local resp = http_post(public_api("/report"), json_encode({ reports = { { monitor_id = 999, is_up = 1 } } }), headers)
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data.results, 1)
    spyweb.assert_eq(body.data.results[1].monitor_id, 999)
    spyweb.assert_eq(body.data.results[1].transition, false)
end

function test_report_and_consensus_transition()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM cluster_monitor_state")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    -- Create central node (automatically by get_or_create_central_node)
    local central = db.get_or_create_central_node()
    spyweb.assert_ne(central, nil)

    -- Create a checker node
    local nprefix, nsecret = cluster_auth.parse_token("check1.secret")
    local checker = db.create_node({ name = "Checker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(checker, nil)

    -- Create a monitor — insert_monitor now seeds cluster_monitor_state as UP
    http_post(api("/monitors"), json_encode({ name = "TestMon", url = "https://test.example.com" }), { ["Content-Type"] = "application/json" })

    local monitors = db.list_all()
    spyweb.assert_eq(#monitors, 1)
    local m_id = monitors[1].id

    -- Verify initial state is UP
    local initial_state = db.get_monitor_consensus_state(m_id)
    spyweb.assert_ne(initial_state, nil)
    spyweb.assert_eq(initial_state.current_status, "UP")

    -- Update settings to make consensus eager
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_min_nodes', '1')")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_quorum_pct', '100')")

    -- Central records its own UP report
    db.upsert_node_report(m_id, central.id, { is_up = 1, status_code = 200, response_time_ms = 50, error_message = "" })

    -- Checker sends DOWN report — triggers UP→DOWN transition
    local headers = { ["Content-Type"] = "application/json", [cluster_auth.HEADER_KEY] = "check1.secret" }
    local resp = http_post(public_api("/report"),
        json_encode({ reports = { {
            monitor_id = m_id, is_up = 0, status_code = 500, response_time_ms = 1000, error_message = "Internal Server Error",
        } } }),
        headers)
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data.results, 1)
    spyweb.assert_eq(body.data.results[1].transition, true)
    spyweb.assert_eq(body.data.results[1].status, "DOWN")

    -- Verify cluster_monitor_state reflects the transition
    local state = db.get_monitor_consensus_state(m_id)
    spyweb.assert_eq(state.current_status, "DOWN")

    -- Same DOWN report again — should skip evaluation (early return)
    local resp2 = http_post(public_api("/report"),
        json_encode({ reports = { {
            monitor_id = m_id, is_up = 0, status_code = 500, response_time_ms = 1000, error_message = "Internal Server Error",
        } } }),
        headers)
    spyweb.assert_eq(resp2.status, 200)
    local body2 = json_decode(resp2.body)
    spyweb.assert_eq(body2.success, true)
    spyweb.assert_eq(#body2.data.results, 1)
    spyweb.assert_eq(body2.data.results[1].transition, false)
    spyweb.assert_eq(body2.data.results[1].skipped, true)
    spyweb.assert_eq(body2.data.results[1].status, "DOWN")
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
    local nprefix, nsecret = cluster_auth.parse_token("node1.secret")
    local node = db.create_node({ name = "Checker One", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    local before_version = db.get_monitors_version()
    http_post(api("/monitors"), json_encode({ name = "ClusterMon", url = "https://cluster.example.com" }), { ["Content-Type"] = "application/json" })
    local after_version = db.get_monitors_version()
    spyweb.assert_eq(after_version, before_version + 1)

    local headers = { [cluster_auth.HEADER_KEY] = "node1.secret" }
    local version_resp = http_get(public_api("/cluster_version"), headers)
    spyweb.assert_eq(version_resp.status, 200)
    spyweb.assert_eq(tonumber(version_resp.body), after_version)

    local export_resp = http_get(public_api("/cluster_export"), headers)
    spyweb.assert_eq(export_resp.status, 200)
    local export_body = json_decode(export_resp.body)
    spyweb.assert_eq(#export_body, 1)
    spyweb.assert_eq(export_body[1].name, "ClusterMon")
    spyweb.assert_eq(export_body[1].url, "https://cluster.example.com")
end

-- =============================================================================
-- Node local_name
-- =============================================================================

function test_report_sets_local_name()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    local nprefix, nsecret = cluster_auth.parse_token("local1.secret")
    local node = db.create_node({ name = "LocalTest", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "local1.secret",
        [cluster_auth.LOCAL_NAME] = "my-laptop",
    }
    http_post(api("/monitors"), json_encode({ name = "LocalMon", url = "https://local.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local resp = http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = monitors[1].id, is_up = 1, status_code = 200, response_time_ms = 50 } } }),
        headers)
    spyweb.assert_eq(resp.status, 200)

    local updated = db.get_node(node.id)
    spyweb.assert_eq(updated.local_name, "my-laptop")
end

function test_list_nodes_returns_local_name()
    db_exec("DELETE FROM nodes")
    local nprefix, nsecret = cluster_auth.parse_token("local2.secret")
    local node = db.create_node({ name = "ListLocal", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    db.update_node_local_name(node.id, "server-alpha")

    local nodes = db.list_nodes()
    spyweb.assert_eq(#nodes, 1)
    spyweb.assert_eq(nodes[1].local_name, "server-alpha")
end

function test_local_name_same_value_no_rewrite()
    db_exec("DELETE FROM nodes")
    local nprefix, nsecret = cluster_auth.parse_token("local3.secret")
    local node = db.create_node({ name = "NoRewrite", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "local3.secret",
        [cluster_auth.LOCAL_NAME] = "stable-name",
    }
    http_post(api("/monitors"), json_encode({ name = "StableMon", url = "https://stable.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()

    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = monitors[1].id, is_up = 1, status_code = 200, response_time_ms = 10 } } }),
        headers)
    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = monitors[1].id, is_up = 1, status_code = 200, response_time_ms = 10 } } }),
        headers)

    local updated = db.get_node(node.id)
    spyweb.assert_eq(updated.local_name, "stable-name")
end

-- =============================================================================
-- treat_4xx_as_down — central report classification
-- =============================================================================

function test_report_4xx_down_when_setting_on()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("4xx1.secret")
    local node = db.create_node({ name = "Checker4xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(api("/monitors"), json_encode({ name = "4xxMon", url = "https://4xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "4xx1.secret",
    }
    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 403, response_time_ms = 50 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 0)
end

function test_report_4xx_kept_when_setting_off()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '0')")

    local nprefix, nsecret = cluster_auth.parse_token("4xx2.secret")
    local node = db.create_node({ name = "Checker4xxOff", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(api("/monitors"), json_encode({ name = "4xxMonOff", url = "https://4xxoff.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "4xx2.secret",
    }
    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 403, response_time_ms = 50 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 1)
end

function test_report_500_down_regardless_of_setting()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("5xx1.secret")
    local node = db.create_node({ name = "Checker5xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(api("/monitors"), json_encode({ name = "5xxMon", url = "https://5xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "5xx1.secret",
    }
    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 0, status_code = 500, response_time_ms = 100 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 0)
end

function test_report_200_up_regardless_of_setting()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("2xx1.secret")
    local node = db.create_node({ name = "Checker2xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(api("/monitors"), json_encode({ name = "2xxMon", url = "https://2xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "2xx1.secret",
    }
    http_post(public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 200, response_time_ms = 30 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 1)
end

-- =============================================================================
-- Batch report insert / multi-report /report handler
-- =============================================================================

function test_upsert_node_reports_batch_insert_and_update()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local central = db.get_or_create_central_node()
    spyweb.assert_ne(central, nil)

    http_post(api("/monitors"), json_encode({ name = "BatchMonA", url = "https://batch-a.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(api("/monitors"), json_encode({ name = "BatchMonB", url = "https://batch-b.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    spyweb.assert_eq(#monitors, 2)
    local mid_a = monitors[1].id
    local mid_b = monitors[2].id

    -- Insert two rows in one batch call
    db.upsert_node_reports_batch({
        { monitor_id = mid_a, node_id = central.id, is_up = 1, status_code = 200, response_time_ms = 42, error_message = "" },
        { monitor_id = mid_b, node_id = central.id, is_up = 0, status_code = 503, response_time_ms = 1200, error_message = "Service Unavailable" },
    })

    local rows_a = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid_a, central.id })
    spyweb.assert_eq(#rows_a, 1)
    spyweb.assert_eq(rows_a[1].is_up, 1)
    spyweb.assert_eq(rows_a[1].status_code, 200)

    local rows_b = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid_b, central.id })
    spyweb.assert_eq(#rows_b, 1)
    spyweb.assert_eq(rows_b[1].is_up, 0)
    spyweb.assert_eq(rows_b[1].status_code, 503)

    -- Second batch: same monitor_id + node_id, updated values — must upsert, not duplicate
    db.upsert_node_reports_batch({
        { monitor_id = mid_a, node_id = central.id, is_up = 0, status_code = 502, response_time_ms = 999, error_message = "Bad Gateway" },
    })

    rows_a = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid_a, central.id })
    spyweb.assert_eq(#rows_a, 1)
    spyweb.assert_eq(rows_a[1].is_up, 0)
    spyweb.assert_eq(rows_a[1].status_code, 502)

    -- Empty batch must not error, and must not add rows
    db.upsert_node_reports_batch({})
    local all = db_query("SELECT * FROM node_reports")
    spyweb.assert_eq(#all, 2)
end

function test_update_monitor_status_batch()
    db_exec("DELETE FROM monitors")

    http_post(api("/monitors"), json_encode({ name = "StatusMonA", url = "https://status-a.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(api("/monitors"), json_encode({ name = "StatusMonB", url = "https://status-b.example.com" }), { ["Content-Type"] = "application/json" })
    local mid_a = db_query("SELECT id FROM monitors WHERE url = ?", { "https://status-a.example.com" })[1].id
    local mid_b = db_query("SELECT id FROM monitors WHERE url = ?", { "https://status-b.example.com" })[1].id
    spyweb.assert_ne(mid_a, nil)
    spyweb.assert_ne(mid_b, nil)

    -- Update both monitors, and include a nonexistent id (deleted mid-race).
    -- The legit rows must update ONLY the 5 status columns (never name/url),
    -- and the nonexistent id must NOT be resurrected.
    local nonexistent = 999999
    db.update_monitor_status_batch({
        { monitor_id = mid_a, is_up = 0, status_code = 503, response_time_ms = 1500, consecutive_failures = 3 },
        { monitor_id = mid_b, is_up = 1, status_code = 200, response_time_ms = 77, consecutive_failures = 0 },
        { monitor_id = nonexistent, is_up = 0, status_code = 500, response_time_ms = 1, consecutive_failures = 5 },
    })

    local row_a = db_query("SELECT * FROM monitors WHERE id = ?", { mid_a })[1]
    spyweb.assert_eq(row_a.is_up, 0)
    spyweb.assert_eq(row_a.last_status_code, 503)
    spyweb.assert_eq(row_a.last_response_time_ms, 1500)
    spyweb.assert_eq(row_a.consecutive_failures, 3)
    spyweb.assert_ne(row_a.updated_at, nil)
    spyweb.assert_eq(row_a.name, "StatusMonA")
    spyweb.assert_eq(row_a.url, "https://status-a.example.com")

    local row_b = db_query("SELECT * FROM monitors WHERE id = ?", { mid_b })[1]
    spyweb.assert_eq(row_b.is_up, 1)
    spyweb.assert_eq(row_b.last_status_code, 200)
    spyweb.assert_eq(row_b.last_response_time_ms, 77)
    spyweb.assert_eq(row_b.consecutive_failures, 0)

    -- Nonexistent id must not have been inserted.
    local ghosts = db_query("SELECT COUNT(*) AS c FROM monitors WHERE id = ?", { nonexistent })
    spyweb.assert_eq(ghosts[1].c, 0)

    -- Empty batch must not error and must not change anything.
    db.update_monitor_status_batch({})
    local total = db_query("SELECT COUNT(*) AS c FROM monitors")
    spyweb.assert_eq(total[1].c, 2)

    db_exec("DELETE FROM monitors")
end

function test_report_batch_multi()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM cluster_monitor_state")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local central = db.get_or_create_central_node()
    spyweb.assert_ne(central, nil)

    local nprefix, nsecret = cluster_auth.parse_token("batch1.secret")
    local checker = db.create_node({ name = "BatchChecker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(checker, nil)

    http_post(api("/monitors"), json_encode({ name = "BatchMonX", url = "https://batchx.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(api("/monitors"), json_encode({ name = "BatchMonY", url = "https://batchy.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    spyweb.assert_eq(#monitors, 2)
    local mid_x = monitors[1].id
    local mid_y = monitors[2].id

    -- Set eager consensus: min_nodes=1, quorum=100%
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_min_nodes', '1')")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_quorum_pct', '100')")

    -- Seed central UP report so checker DOWN triggers a transition
    db.upsert_node_report(mid_x, central.id, { is_up = 1, status_code = 200, response_time_ms = 30, error_message = "" })
    db.upsert_node_report(mid_y, central.id, { is_up = 1, status_code = 200, response_time_ms = 25, error_message = "" })

    -- Checker posts two reports in one batch: X=DOWN, Y=UP
    local headers = { ["Content-Type"] = "application/json", [cluster_auth.HEADER_KEY] = "batch1.secret" }
    local resp = http_post(public_api("/report"),
        json_encode({ reports = {
            { monitor_id = mid_x, is_up = 0, status_code = 500, response_time_ms = 1500, error_message = "timeout" },
            { monitor_id = mid_y, is_up = 1, status_code = 200, response_time_ms = 40 },
        } }),
        headers)
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data.results, 2)

    -- Find each result by monitor_id
    local res_x, res_y
    for _, r in ipairs(body.data.results) do
        if r.monitor_id == mid_x then res_x = r
        elseif r.monitor_id == mid_y then res_y = r end
    end
    spyweb.assert_ne(res_x, nil)
    spyweb.assert_ne(res_y, nil)

    -- X: two DOWN votes (central + checker), single node required → transition to DOWN
    spyweb.assert_eq(res_x.transition, true)
    spyweb.assert_eq(res_x.status, "DOWN")

    -- Y: UP vote only, central also UP → no transition (already UP)
    spyweb.assert_eq(res_y.transition, false)
    spyweb.assert_eq(res_y.status, "UP")

    -- Verify node_reports rows: 2 monitors × (central + checker) nodes = 4, no dupes
    local rows = db_query("SELECT * FROM node_reports")
    spyweb.assert_eq(#rows, 4)

    local state_x = db.get_monitor_consensus_state(mid_x)
    spyweb.assert_eq(state_x.current_status, "DOWN")

    local state_y = db.get_monitor_consensus_state(mid_y)
    spyweb.assert_eq(state_y.current_status, "UP")
end
