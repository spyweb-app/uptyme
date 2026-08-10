local db = require("lib.db")
local check_buffer = require("lib.check_buffer")

local N = 1000

local function seed(n)
    db.ensure_schema()
    db_exec("DELETE FROM check_history")
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM node_reports")
    for i = 1, n do
        db_exec("INSERT INTO monitors (name, url, interval_sec) VALUES (?, ?, 60)", {
            "Bench" .. i,
            "https://bench" .. i .. ".example.com",
        })
    end
    return db_query("SELECT id FROM monitors ORDER BY id")
end

local function bench(label, fn)
    local start = os.clock()
    fn()
    local ms = (os.clock() - start) * 1000
    print(string.format("[bench] %-22s %9.2f ms total  %8.4f ms/op  (%d ops)", label, ms, ms / N, N))
end

local function bench_history_per_row(monitors)
    for _, m in ipairs(monitors) do
        db.insert_check(m.id, 200, 45, 1, "")
    end
end

local function bench_history_batch(monitors)
    local rows = {}
    for _, m in ipairs(monitors) do
        table.insert(rows, { monitor_id = m.id, status_code = 200, response_time_ms = 45, is_up = 1, error_message = "" })
    end
    db.insert_check_history_batch(rows)
end

local function bench_node_report_per_row(monitors, node)
    for _, m in ipairs(monitors) do
        db.upsert_node_report(m.id, node.id, { is_up = 1, status_code = 200, response_time_ms = 45, error_message = "" })
    end
end

local function bench_node_report_batch(monitors, node)
    local rows = {}
    for _, m in ipairs(monitors) do
        table.insert(rows, { monitor_id = m.id, node_id = node.id, is_up = 1, status_code = 200, response_time_ms = 45, error_message = "" })
    end
    db.upsert_node_reports_batch(rows)
end

local function bench_after_fetch_per_row(monitors)
    for _, m in ipairs(monitors) do
        db.update_monitor_status(m.id, 1, 200, 45, 0)
        db.insert_check(m.id, 200, 45, 1, "")
    end
end

local function bench_after_fetch_batch(monitors)
    check_buffer.drain_history()
    for _, m in ipairs(monitors) do
        db.update_monitor_status(m.id, 1, 200, 45, 0)
        check_buffer.push_history({ monitor_id = m.id, status_code = 200, response_time_ms = 45, is_up = 1, error_message = "", checked_at = os.time() })
    end
    db.insert_check_history_batch(check_buffer.drain_history())
end

local function monitor_status_rows(monitors)
    local rows = {}
    for _, m in ipairs(monitors) do
        table.insert(rows, { monitor_id = m.id, is_up = 1, status_code = 200, response_time_ms = 45, consecutive_failures = 0 })
    end
    return rows
end

local function bench_monitor_status_per_row(monitors)
    for _, m in ipairs(monitors) do
        db.update_monitor_status(m.id, 1, 200, 45, 0)
    end
end

local function bench_monitor_status_batch(monitors)
    db.update_monitor_status_batch(monitor_status_rows(monitors))
end

function test_bench()
    local monitors = seed(N)
    db.get_or_create_central_node()
    local node = db.get_or_create_central_node()

    bench("check_history per-row", function() bench_history_per_row(monitors) end)
    bench("check_history batch", function() bench_history_batch(monitors) end)
    bench("node_report per-row", function() bench_node_report_per_row(monitors, node) end)
    bench("node_report batch", function() bench_node_report_batch(monitors, node) end)
    bench("after_fetch per-row", function() bench_after_fetch_per_row(monitors) end)
    bench("after_fetch batch", function() bench_after_fetch_batch(monitors) end)
    db_exec("DELETE FROM monitors")
    monitors = seed(N)
    bench("monitor_status per-row", function() bench_monitor_status_per_row(monitors) end)
    bench("monitor_status batch", function() bench_monitor_status_batch(monitors) end)
end