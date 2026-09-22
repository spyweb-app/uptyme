local H = require("server.tests.helpers")
local db = require("lib.db")
local stats = require("handlers.stats")
local runtime_config = require("lib.runtime_config")

local function seed_two_monitors()
    db_exec("DELETE FROM monitors")
    local a = db_query("INSERT INTO monitors (name, url) VALUES ('A', 'https://a.example.com') RETURNING id")[1]
    local b = db_query("INSERT INTO monitors (name, url) VALUES ('B', 'https://b.example.com') RETURNING id")[1]
    return a.id, b.id
end

function test_get_stats_standalone()
    db.ensure_schema()
    local aid, bid = seed_two_monitors()
    local now = os.time()
    local day2 = now - 86400

    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { aid, day2 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { bid, day2 })
    db_exec("UPDATE monitors SET is_up = 0 WHERE id = ?", { bid })

    -- A paused monitor counts toward total but not up/down
    db_exec("INSERT INTO monitors (name, url, enabled) VALUES ('Paused', 'https://paused.example.com', 0)")

    local resp = http_get(H.api("/stats"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)

    local agg = body.data.aggregates
    spyweb.assert_eq(agg.total, 3)
    spyweb.assert_eq(agg.enabled, 2)
    spyweb.assert_eq(agg.disabled, 1)
    spyweb.assert_eq(agg.up, 1)
    spyweb.assert_eq(agg.down, 1) -- bid is_down check above
    spyweb.assert_eq(agg.unknown, 0)
    spyweb.assert_eq(agg.active_incidents, 1)

    -- day2 has 2 checks: A up, B down → 50% uptime
    local last = nil
    for _, s in ipairs(body.data.series) do
        if s.period == os.date("!%Y-%m-%d", day2) then last = s end
    end
    spyweb.assert_ne(last, nil)
    spyweb.assert_eq(last.total, 2)
    spyweb.assert_eq(last.up_count, 1)
    spyweb.assert_eq(last.uptime, 50)
end

function test_stats_handler_checker_404()
    db.ensure_schema()
    local orig_role = runtime_config.role
    runtime_config.role = function() return "checker" end

    local resp = stats.get({})
    spyweb.assert_eq(resp.status, 404)

    runtime_config.role = orig_role
end

function test_get_stats_central_incidents()
    db.ensure_schema()
    local aid, _ = seed_two_monitors()
    local now = os.time()
    db_exec("INSERT INTO consensus_transitions (monitor_id, status, transitioned_at) VALUES (?, 'DOWN', ?)", { aid, now })

    local resp = http_get(H.api("/stats"))
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    local inc = body.data.incidents
    spyweb.assert_eq(#inc, 1)
    spyweb.assert_eq(inc[1].monitor_id, aid)
    spyweb.assert_eq(inc[1].status, "DOWN")
    spyweb.assert_ne(inc[1].started_at, nil)
end

function test_get_global_stats_standalone_incidents()
    db.ensure_schema()
    local aid, _ = seed_two_monitors()
    local now = os.time()
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { aid, now - 3600 })    -- up
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { aid, now - 1800 })    -- down transition
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { aid, now })            -- recovered

    local incidents = db.get_incidents(nil, 20, "standalone")
    spyweb.assert_eq(#incidents, 1)
    spyweb.assert_eq(incidents[1].status, "UP")
    spyweb.assert_ne(incidents[1].resolved_at, nil)
end

function test_incident_transition_cap_is_per_monitor()
    db.ensure_schema()
    local aid, bid = seed_two_monitors()
    local now = os.time()

    for i = 1, 200 do
        local status = i % 2 == 0 and "UP" or "DOWN"
        db_exec([[INSERT INTO consensus_transitions (monitor_id, status, transitioned_at)
            VALUES (?, ?, ?)]], { aid, status, now - 1000 + i })
    end
    db_exec([[INSERT INTO consensus_transitions (monitor_id, status, transitioned_at)
        VALUES (?, 'DOWN', ?)]], { bid, now })

    local incidents = db.get_incidents({ aid, bid }, nil, "central")
    local found_b = false
    for _, incident in ipairs(incidents) do
        if incident.monitor_id == bid then found_b = true end
    end
    spyweb.assert_eq(found_b, true)
end
