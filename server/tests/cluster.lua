local H = require("server.tests.helpers")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")

local function clear_monitor_create_throttle()
    global_store_delete("ratelimit:admin:monitors:create:127.0.0.1:start")
    global_store_delete("ratelimit:admin:monitors:create:127.0.0.1:count")
end

function test_report_requires_auth()
    db_exec("DELETE FROM nodes")
    local resp = http_post(H.public_api("/report"), json_encode({ reports = { { monitor_id = 1, is_up = 1 } } }), { ["Content-Type"] = "application/json" })
    spyweb.assert_eq(resp.status, 401)
end

function test_report_bad_monitor()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    local nprefix, nsecret = cluster_auth.parse_token("check1.secret")
    local node = db.create_node({ name = "Checker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)
    local headers = { ["Content-Type"] = "application/json", [cluster_auth.HEADER_KEY] = "check1.secret" }
    local resp = http_post(H.public_api("/report"), json_encode({ reports = { { monitor_id = 999, is_up = 1 } } }), headers)
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(#body.data.results, 1)
    spyweb.assert_eq(body.data.results[1].monitor_id, 999)
    spyweb.assert_eq(body.data.results[1].transition, false)
end

function test_report_and_consensus_transition()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM cluster_monitor_state")
    db_exec("DELETE FROM consensus_transitions")
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
    http_post(H.api("/monitors"), json_encode({ name = "TestMon", url = "https://test.example.com" }), { ["Content-Type"] = "application/json" })

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
    local resp = http_post(H.public_api("/report"),
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
    local resp2 = http_post(H.public_api("/report"),
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

function test_cluster_version_requires_auth()
    local resp = http_get(H.public_api("/cluster_version"))
    spyweb.assert_eq(resp.status, 401)
end

function test_cluster_version_and_export()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    local nprefix, nsecret = cluster_auth.parse_token("node1.secret")
    local node = db.create_node({ name = "Checker One", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    local before_version = db.get_monitors_version()
    http_post(H.api("/monitors"), json_encode({ name = "ClusterMon", url = "https://cluster.example.com" }), { ["Content-Type"] = "application/json" })
    local after_version = db.get_monitors_version()
    spyweb.assert_eq(after_version, before_version + 1)

    local headers = { [cluster_auth.HEADER_KEY] = "node1.secret" }
    local version_resp = http_get(H.public_api("/cluster_version"), headers)
    spyweb.assert_eq(version_resp.status, 200)
    spyweb.assert_eq(tonumber(version_resp.body), after_version)

    local export_resp = http_get(H.public_api("/cluster_export"), headers)
    spyweb.assert_eq(export_resp.status, 200)
    local export_body = json_decode(export_resp.body)
    spyweb.assert_eq(#export_body, 1)
    spyweb.assert_eq(export_body[1].name, "ClusterMon")
    spyweb.assert_eq(export_body[1].url, "https://cluster.example.com")
end

function test_report_sets_local_name()
    clear_monitor_create_throttle()
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
    http_post(H.api("/monitors"), json_encode({ name = "LocalMon", url = "https://local.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local resp = http_post(H.public_api("/report"),
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
    http_post(H.api("/monitors"), json_encode({ name = "StableMon", url = "https://stable.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()

    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = monitors[1].id, is_up = 1, status_code = 200, response_time_ms = 10 } } }),
        headers)
    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = monitors[1].id, is_up = 1, status_code = 200, response_time_ms = 10 } } }),
        headers)

    local updated = db.get_node(node.id)
    spyweb.assert_eq(updated.local_name, "stable-name")
end

function test_report_4xx_down_when_setting_on()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("4xx1.secret")
    local node = db.create_node({ name = "Checker4xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(H.api("/monitors"), json_encode({ name = "4xxMon", url = "https://4xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "4xx1.secret",
    }
    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 403, response_time_ms = 50 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 0)
end

function test_report_4xx_kept_when_setting_off()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '0')")

    local nprefix, nsecret = cluster_auth.parse_token("4xx2.secret")
    local node = db.create_node({ name = "Checker4xxOff", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(H.api("/monitors"), json_encode({ name = "4xxMonOff", url = "https://4xxoff.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "4xx2.secret",
    }
    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 403, response_time_ms = 50 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 1)
end

function test_report_500_down_regardless_of_setting()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("5xx1.secret")
    local node = db.create_node({ name = "Checker5xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(H.api("/monitors"), json_encode({ name = "5xxMon", url = "https://5xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "5xx1.secret",
    }
    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 0, status_code = 500, response_time_ms = 100 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 0)
end

function test_report_200_up_regardless_of_setting()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local nprefix, nsecret = cluster_auth.parse_token("2xx1.secret")
    local node = db.create_node({ name = "Checker2xx", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(node, nil)

    http_post(H.api("/monitors"), json_encode({ name = "2xxMon", url = "https://2xx.example.com" }), { ["Content-Type"] = "application/json" })
    local monitors = db.list_all()
    local mid = monitors[1].id

    local headers = {
        ["Content-Type"] = "application/json",
        [cluster_auth.HEADER_KEY] = "2xx1.secret",
    }
    http_post(H.public_api("/report"),
        json_encode({ reports = { { monitor_id = mid, is_up = 1, status_code = 200, response_time_ms = 30 } } }),
        headers)

    local rows = db_query("SELECT * FROM node_reports WHERE monitor_id = ? AND node_id = ?", { mid, node.id })
    spyweb.assert_eq(#rows, 1)
    spyweb.assert_eq(rows[1].is_up, 1)
end

function test_upsert_node_reports_batch_insert_and_update()
    clear_monitor_create_throttle()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local central = db.get_or_create_central_node()
    spyweb.assert_ne(central, nil)

    http_post(H.api("/monitors"), json_encode({ name = "BatchMonA", url = "https://batch-a.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(H.api("/monitors"), json_encode({ name = "BatchMonB", url = "https://batch-b.example.com" }), { ["Content-Type"] = "application/json" })
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
    clear_monitor_create_throttle()
    db_exec("DELETE FROM monitors")

    http_post(H.api("/monitors"), json_encode({ name = "StatusMonA", url = "https://status-a.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(H.api("/monitors"), json_encode({ name = "StatusMonB", url = "https://status-b.example.com" }), { ["Content-Type"] = "application/json" })
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
    clear_monitor_create_throttle()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM cluster_monitor_state")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local central = db.get_or_create_central_node()
    spyweb.assert_ne(central, nil)

    local nprefix, nsecret = cluster_auth.parse_token("batch1.secret")
    local checker = db.create_node({ name = "BatchChecker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(checker, nil)

    http_post(H.api("/monitors"), json_encode({ name = "BatchMonX", url = "https://batchx.example.com" }), { ["Content-Type"] = "application/json" })
    http_post(H.api("/monitors"), json_encode({ name = "BatchMonY", url = "https://batchy.example.com" }), { ["Content-Type"] = "application/json" })
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
    local resp = http_post(H.public_api("/report"),
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

function test_consensus_initial_down_logs_transition()
    db_exec("DELETE FROM node_reports")
    db_exec("DELETE FROM cluster_monitor_state")
    db_exec("DELETE FROM consensus_transitions")
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_min_nodes', '1')")
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('consensus_quorum_pct', '100')")

    local consensus = require("lib.consensus")

    -- Create a checker node
    local nprefix, nsecret = cluster_auth.parse_token("bugfix1.secret")
    local checker = db.create_node({ name = "Checker", role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
    spyweb.assert_ne(checker, nil)
    -- Set last_seen_at so the node is considered live by consensus evaluator
    db_exec("UPDATE nodes SET last_seen_at = ? WHERE id = ?", { os.time(), checker.id })

    -- Create a monitor with NO cluster_monitor_state row (simulates fresh upgrade)
    local m_id = db_query("INSERT INTO monitors (name, url) VALUES ('NoState', 'https://nostate.example.com') RETURNING id")[1].id

    -- Insert a DOWN report for the checker node
    db.upsert_node_report(m_id, checker.id, { is_up = 0, status_code = 500, response_time_ms = 1000, error_message = "fail" })

    -- First evaluation: DOWN result on monitor with no prior state
    local result = consensus.evaluate(m_id, 0)
    spyweb.assert_eq(result.status, "DOWN")

    -- Verify cluster_monitor_state was created
    local state = db.get_monitor_consensus_state(m_id)
    spyweb.assert_ne(state, nil)
    spyweb.assert_eq(state.current_status, "DOWN")

    -- Verify transition row was logged (the bug fix)
    local transitions = db_query("SELECT * FROM consensus_transitions WHERE monitor_id = ? ORDER BY transitioned_at", { m_id })
    spyweb.assert_eq(#transitions, 1)
    spyweb.assert_eq(transitions[1].status, "DOWN")
end
