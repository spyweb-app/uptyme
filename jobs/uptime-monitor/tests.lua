local db = require("lib.db")
local check = require("lib.check_pipeline")
local alert = require("alert")
local check_buffer = require("lib.check_buffer")
local role_strategies = require("lib.role_strategies")

-- =============================================================================
-- Helpers
-- =============================================================================

local function flush_checks()
    db.insert_check_history_batch(check_buffer.drain_history())
end

local function flush_status()
    db.update_monitor_status_batch(check_buffer.drain_status())
end

function make_monitor(name, url, was_up)
    db.ensure_schema()
    db_exec("DELETE FROM monitors")
    db_exec("DELETE FROM check_history")
    local rows = db_query("INSERT INTO monitors (name, url, interval_sec, is_up) VALUES (?, ?, 60, ?) RETURNING id", { name, url, was_up and 1 or 0 })
    return rows[1].id
end

function make_ctx(id, overrides)
    local ctx = {
        shared = {
            monitor_id = id,
            monitor_name = "Test",
            monitor_url = "https://test.com",
            check_value = "",
            was_up = true,
            prev_failures = 0,
            desktop_notify = 0,
            central_node = db.get_or_create_central_node(),
        }
    }
    if overrides then
        for k, v in pairs(overrides) do ctx.shared[k] = v end
    end
    return ctx
end

function capture_http_post()
    local captured
    http_post = function(url, body, headers)
        captured = { url = url, body = json_decode(body), headers = headers }
        return { status = 200 }
    end
    return function() return captured end
end

notify = function() end

-- =============================================================================
-- Schema / DB
-- =============================================================================

function test_schema_created()
    db.ensure_schema()
    local rows = db_query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    local names = {}
    for _, r in ipairs(rows) do
        table.insert(names, r.name)
    end
    local expected = { monitors = true, check_history = true, settings = true, notification_channels = true, monitor_notifications = true }
    for _, name in ipairs(names) do
        expected[name] = nil
    end
    local missing = {}
    for k in pairs(expected) do
        table.insert(missing, k)
    end
    spyweb.assert_eq(#missing, 0, "missing tables: " .. table.concat(missing, ", "))
end

function test_insert_monitor()
    db.ensure_schema()
    local ok, _ = db.insert_monitor({ name = "Test", url = "https://test.example.com", interval_sec = 60 })
    spyweb.assert_eq(ok, true)
    local row = db.get_by_url("https://test.example.com")
    spyweb.assert_ne(row, nil)
    spyweb.assert_eq(row.name, "Test")
    spyweb.assert_eq(row.interval_sec, 60)
end

-- =============================================================================
-- db.get_summary — grouping
-- =============================================================================

function test_get_summary_daily()
    db.ensure_schema()
    local id = make_monitor("DailySummary", "https://daily-summary.example.com", true)
    local now = os.time()

    -- Insert: 2 checks today (1 up), 3 checks yesterday (2 up)
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { id, now })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 86400 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 86400 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { id, now - 86400 })

    local rows = db.get_summary(id, 2, "day")
    spyweb.assert_eq(#rows, 2)

    -- row order is DESC (most recent first)
    spyweb.assert_eq(rows[1].total, 2)
    spyweb.assert_eq(rows[1].up_count, 1)
    spyweb.assert_eq(rows[1].down_checks, 1)
    spyweb.assert_eq(rows[1].blocked_checks, 0)
    spyweb.assert_eq(rows[2].total, 3)
    spyweb.assert_eq(rows[2].up_count, 2)
    spyweb.assert_eq(rows[2].down_checks, 1)
    spyweb.assert_eq(rows[2].blocked_checks, 0)
end

function test_get_summary_hourly()
    db.ensure_schema()
    local id = make_monitor("HourlySummary", "https://hourly-summary.example.com", true)
    local now = os.time()

    -- Insert across 3 hours:
    -- hour -2 (2 hrs ago): 2 checks, both up
    -- hour -1 (1 hr ago):  3 checks, 1 down
    -- hour 0  (now):       1 check,  1 up
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 7200 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 7200 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { id, now - 3600 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 3600 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now - 3600 })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, now })

    local rows = db.get_summary(id, 1, "hour")
    spyweb.assert_eq(#rows, 3, "expected 3 hourly buckets")

    -- most recent first
    spyweb.assert_eq(rows[1].total, 1, "latest hour: total")
    spyweb.assert_eq(rows[1].up_count, 1, "latest hour: up")
    spyweb.assert_eq(rows[1].down_checks, 0, "latest hour: down")
    spyweb.assert_eq(rows[2].total, 3, "middle hour: total")
    spyweb.assert_eq(rows[2].up_count, 2, "middle hour: up")
    spyweb.assert_eq(rows[2].down_checks, 1, "middle hour: down")
    spyweb.assert_eq(rows[3].total, 2, "earliest hour: total")
    spyweb.assert_eq(rows[3].up_count, 2, "earliest hour: up")
    spyweb.assert_eq(rows[3].down_checks, 0, "earliest hour: down")

    -- period should be ISO-hour format (ends with :00:00)
    spyweb.assert_ne(rows[1].period:match("T%d%d:00:00$"), nil, "hour format")
end

function test_get_summary_halfday()
    db.ensure_schema()
    local id = make_monitor("HalfdaySummary", "https://halfday-summary.example.com", true)
    local now = os.time()
    -- Start of today in UTC
    local today_start = now - (now % 86400)

    -- Insert at 2 AM today (AM bucket), 2 PM today (PM bucket), 2 AM yesterday (AM bucket)
    local am_today = today_start + 7200      -- 2 AM today
    local pm_today = today_start + 50400     -- 2 PM today
    local am_yesterday = today_start - 86400 + 7200  -- 2 AM yesterday

    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, am_today })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, am_today })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 0, ?)", { id, pm_today })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, pm_today })
    db_exec("INSERT INTO check_history (monitor_id, is_up, checked_at) VALUES (?, 1, ?)", { id, am_yesterday })

    local rows = db.get_summary(id, 2, "halfday")
    spyweb.assert_eq(#rows, 3, "expected 3 half-day buckets")

    -- most recent first: today PM, today AM, yesterday AM
    spyweb.assert_eq(rows[1].total, 2, "today PM: total")
    spyweb.assert_eq(rows[1].up_count, 1, "today PM: up")
    spyweb.assert_eq(rows[1].down_checks, 1, "today PM: down")
    spyweb.assert_eq(rows[2].total, 2, "today AM: total")
    spyweb.assert_eq(rows[2].up_count, 2, "today AM: up")
    spyweb.assert_eq(rows[2].down_checks, 0, "today AM: down")
    spyweb.assert_eq(rows[3].total, 1, "yesterday AM: total")
    spyweb.assert_eq(rows[3].up_count, 1, "yesterday AM: up")
    spyweb.assert_eq(rows[3].down_checks, 0, "yesterday AM: down")

    -- period should end with T00:00:00 for AM, T12:00:00 for PM
    spyweb.assert_eq(rows[1].period:match("T%d%d:%d%d:%d%d$"), "T12:00:00", "today PM format")
    spyweb.assert_eq(rows[2].period:match("T%d%d:%d%d:%d%d$"), "T00:00:00", "today AM format")
end

-- =============================================================================
-- check.content_check
-- =============================================================================

function test_check_content_found()
    local r = check.check_content("hello world this is a test", "world")
    spyweb.assert_eq(r, nil)
end

function test_check_content_missing()
    local r = check.check_content("hello world", "nope")
    spyweb.assert_ne(r, nil)
    spyweb.assert_eq(r.err, "Expected content not found: nope")
end

function test_check_content_empty_value()
    local r = check.check_content("hello", "")
    spyweb.assert_eq(r, nil)
end

function test_check_content_no_body()
    local r = check.check_content(nil, "hello")
    spyweb.assert_ne(r, nil)
    spyweb.assert_eq(r.err, "No response body to check")
end

-- =============================================================================
-- check.classify_status
-- =============================================================================

function test_classify_status_200()
    local r = check.classify_status({ ok = true, response = { status = 200 } })
    spyweb.assert_eq(r.is_up, 1)
    spyweb.assert_eq(r.severity, "UP")
    spyweb.assert_eq(r.status_code, 200)
end

function test_classify_status_403()
    local r = check.classify_status({ ok = true, response = { status = 403 } })
    spyweb.assert_eq(r.is_up, 1)
    spyweb.assert_eq(r.severity, "BLOCKED")
    spyweb.assert_eq(r.status_code, 403)
end

function test_classify_status_500()
    local r = check.classify_status({ ok = true, response = { status = 500 } })
    spyweb.assert_eq(r.is_up, 0)
    spyweb.assert_eq(r.severity, "DOWN")
    spyweb.assert_eq(r.status_code, 500)
end

function test_classify_status_timeout()
    local r = check.classify_status({ ok = false, error = { message = "timeout" } })
    spyweb.assert_eq(r.is_up, 0)
    spyweb.assert_eq(r.severity, "DOWN")
    spyweb.assert_eq(r.status_code, 0)
    spyweb.assert_eq(r.err, "timeout")
end

-- =============================================================================
-- alert.compute_failures
-- =============================================================================

function test_compute_failures_down()
    spyweb.assert_eq(alert.compute_failures(0, "DOWN", 5), 6)
end

function test_compute_failures_blocked()
    spyweb.assert_eq(alert.compute_failures(1, "BLOCKED", 3), 3)
end

function test_compute_failures_up()
    spyweb.assert_eq(alert.compute_failures(1, "UP", 5), 0)
end

-- =============================================================================
-- alert.maybe_alert — decision tree
-- =============================================================================

function test_maybe_alert_first_down()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local s = { monitor_id = 1, was_up = true, desktop_notify = 0 }
    alert.maybe_alert(s, "DOWN", 1, os.time(), 500, "connection refused")
    spyweb.assert_ne(alerted, false)
    spyweb.assert_eq(alerted.severity, "DOWN")
    spyweb.assert_eq(alerted.message, "Status changed from UP to DOWN: connection refused")
end

function test_maybe_alert_skips_on_cooldown()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local now = os.time()
    store_set("alerted:1", tostring(now))
    local s = { monitor_id = 1, was_up = false, desktop_notify = 0 }
    alert.maybe_alert(s, "DOWN", 5, now, 500, "still failing")
    spyweb.assert_eq(alerted, false)
end

function test_maybe_alert_fires_after_cooldown()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local now = os.time()
    store_set("alerted:1", tostring(now - 600))
    local s = { monitor_id = 1, was_up = false, desktop_notify = 0 }
    alert.maybe_alert(s, "DOWN", 5, now, 500, "still failing")
    spyweb.assert_ne(alerted, false)
    spyweb.assert_eq(alerted.message, "Consecutive failures: 5 - still failing")
end

function test_maybe_alert_blocked()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local s = { monitor_id = 1, was_up = true, desktop_notify = 0 }
    alert.maybe_alert(s, "BLOCKED", 0, os.time(), 403, "")
    spyweb.assert_ne(alerted, false)
    spyweb.assert_eq(alerted.severity, "BLOCKED")
    spyweb.assert_eq(alerted.message, "HTTP 403 - Access denied by server")
end

function test_maybe_alert_blocked_skips_when_already_down()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local s = { monitor_id = 1, was_up = false, desktop_notify = 0 }
    alert.maybe_alert(s, "BLOCKED", 5, os.time(), 403, "")
    spyweb.assert_eq(alerted, false)
end

function test_maybe_alert_recovered()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local s = { monitor_id = 1, was_up = false, desktop_notify = 0 }
    alert.maybe_alert(s, "UP", 0, os.time(), 200, "")
    spyweb.assert_ne(alerted, false)
    spyweb.assert_eq(alerted.severity, "UP")
    spyweb.assert_eq(alerted.message, "Monitor recovered - HTTP 200")
end

function test_maybe_alert_noop_when_already_up()
    local alerted = false
    alert.do_alert = function(s, severity, message)
        alerted = { severity = severity, message = message }
    end

    db.ensure_schema()
    local s = { monitor_id = 1, was_up = true, desktop_notify = 0 }
    alert.maybe_alert(s, "UP", 0, os.time(), 200, "")
    spyweb.assert_eq(alerted, false)
end

-- =============================================================================
-- Notifier — channel payload structure
-- =============================================================================

function test_webhook_payload()
    local get = capture_http_post()
    local svc = require("lib.notifier.webhook")
    svc.send({ url = "https://hook.example.com" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.url, "https://hook.example.com")
    spyweb.assert_eq(c.body.event, "monitor_alert")
    spyweb.assert_eq(c.body.severity, "DOWN")
    spyweb.assert_eq(c.body.monitor, "Test")
    spyweb.assert_eq(c.headers["Content-Type"], "application/json")
end

function test_webhook_payload_up()
    local get = capture_http_post()
    local svc = require("lib.notifier.webhook")
    svc.send({ url = "https://hook.example.com" }, {
        monitor = "Test", url = "https://test.com", severity = "UP", message = "recovered", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.body.severity, "UP")
    spyweb.assert_eq(c.body.message, "recovered")
end

function test_discord_payload()
    local get = capture_http_post()
    local svc = require("lib.notifier.discord")
    svc.send({ url = "https://discord.com/api/webhooks/xxx" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.url, "https://discord.com/api/webhooks/xxx")
    spyweb.assert_eq(c.body.embeds[1].title, "DOWN: Test")
    spyweb.assert_eq(c.body.embeds[1].description, "msg")
    spyweb.assert_eq(c.body.embeds[1].color, 15548997)
    spyweb.assert_eq(c.body.embeds[1].timestamp, os.date("!%Y-%m-%dT%H:%M:%SZ", 1000))
end

function test_discord_payload_color_up()
    local get = capture_http_post()
    local svc = require("lib.notifier.discord")
    svc.send({ url = "https://discord.com/api/webhooks/xxx" }, {
        monitor = "Test", url = "https://test.com", severity = "UP", message = "up", timestamp = 1000
    })
    spyweb.assert_eq(get().body.embeds[1].color, 5763719)
end

function test_slack_payload()
    local get = capture_http_post()
    local svc = require("lib.notifier.slack")
    svc.send({ url = "https://hooks.slack.com/xxx" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.url, "https://hooks.slack.com/xxx")
    spyweb.assert_eq(c.body.attachments[1].blocks[1].text.text, "DOWN: Test")
    spyweb.assert_eq(c.body.attachments[1].blocks[2].text.text, "msg")
    spyweb.assert_eq(c.body.attachments[1].color, "#ef4444")
end

function test_slack_payload_color_up()
    local get = capture_http_post()
    local svc = require("lib.notifier.slack")
    svc.send({ url = "https://hooks.slack.com/xxx" }, {
        monitor = "Test", url = "https://test.com", severity = "UP", message = "up", timestamp = 1000
    })
    spyweb.assert_eq(get().body.attachments[1].color, "#22c55e")
end

function test_ntfy_payload()
    local get = capture_http_post()
    local svc = require("lib.notifier.ntfy")
    svc.send({ url = "https://ntfy.sh", topic = "alerts", token = "tk_test" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.url, "https://ntfy.sh/alerts")
    spyweb.assert_eq(c.body.topic, "alerts")
    spyweb.assert_eq(c.body.title, "DOWN: Test")
    spyweb.assert_eq(c.body.priority, 4)
    spyweb.assert_eq(c.headers["Authorization"], "Bearer tk_test")
end

function test_ntfy_payload_no_auth()
    local get = capture_http_post()
    local svc = require("lib.notifier.ntfy")
    svc.send({ url = "https://ntfy.sh", topic = "alerts" }, {
        monitor = "Test", url = "https://test.com", severity = "UP", message = "up", timestamp = 1000
    })
    spyweb.assert_eq(get().headers["Authorization"], nil)
    spyweb.assert_eq(get().body.priority, 3)
end

function test_email_sendgrid_payload()
    local get = capture_http_post()
    local svc = require("lib.notifier.email")
    svc.send({ provider = "sendgrid", to = "user@example.com", from = "alert@uptyme", api_key = "SG.test" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    local c = get()
    spyweb.assert_eq(c.url, "https://api.sendgrid.com/v3/mail/send")
    spyweb.assert_eq(c.body.personalizations[1].to[1].email, "user@example.com")
    spyweb.assert_eq(c.body.from.email, "alert@uptyme")
    spyweb.assert_eq(c.headers["Authorization"], "Bearer SG.test")
end

function test_email_missing_provider_defaults_to_sendgrid()
    local url
    http_post = function(u) url = u end
    local svc = require("lib.notifier.email")
    svc.send({ to = "user@example.com", from = "alert@uptyme", api_key = "SG.test" }, {
        monitor = "Test", url = "https://test.com", severity = "DOWN", message = "msg", timestamp = 1000
    })
    spyweb.assert_eq(url, "https://api.sendgrid.com/v3/mail/send")
end

-- =============================================================================
-- before_fetch
-- =============================================================================

function test_before_fetch_claims_due()
    db.ensure_schema()
    db_exec("DELETE FROM monitors")
    db_exec("INSERT INTO monitors (name, url, interval_sec, last_check_at) VALUES ('Due', 'https://due.example.com', 10, 0)")
    db_exec("INSERT INTO monitors (name, url, interval_sec, last_check_at) VALUES ('Future', 'https://future.example.com', 999999, ?)", { os.time() })

    local req = { url = "", headers = {} }
    local ctx = { shared = {} }
    local result = before_fetch(req, ctx)

    spyweb.assert_ne(result, nil)
    spyweb.assert_eq(req.url, "https://due.example.com")
    spyweb.assert_eq(ctx.shared.monitor_name, "Due")
end

function test_before_fetch_returns_nil_when_none_due()
    db.ensure_schema()
    db_exec("DELETE FROM monitors")
    db_exec("INSERT INTO monitors (name, url, interval_sec, last_check_at) VALUES ('Future', 'https://future.example.com', 999999, ?)", { os.time() })

    local req = { url = "", headers = {} }
    local ctx = { shared = {} }
    local result = before_fetch(req, ctx)

    spyweb.assert_eq(result, nil)
end

-- =============================================================================
-- after_fetch — end-to-end pipeline
-- =============================================================================

function test_after_fetch_records_up()
    local id = make_monitor("UpTest", "https://up.example.com", true)
    local ctx = make_ctx(id)
    local fetch_result = {
        ok = true,
        response = { status = 200, url = "https://up.example.com", body = "ok", time_ms = 50 },
        request = { url = "https://up.example.com" },
    }

    local result = after_fetch(fetch_result, ctx)
    spyweb.assert_eq(result, nil)

    flush_status()

    local monitor = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    spyweb.assert_eq(monitor[1].is_up, 1)
    spyweb.assert_eq(monitor[1].consecutive_failures, 0)

    flush_checks()

    local history = db_query("SELECT * FROM check_history WHERE monitor_id = ?", { id })
    spyweb.assert_eq(#history, 1)
    spyweb.assert_eq(history[1].is_up, 1)
end

function test_after_fetch_records_down()
    local id = make_monitor("DownTest", "https://down.example.com", true)
    local ctx = make_ctx(id)
    local fetch_result = {
        ok = false,
        error = { message = "Connection refused" },
        request = { url = "https://down.example.com" },
    }

    local result = after_fetch(fetch_result, ctx)
    spyweb.assert_eq(result, nil)

    flush_status()

    local monitor = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    spyweb.assert_eq(monitor[1].is_up, 0)
    spyweb.assert_eq(monitor[1].consecutive_failures, 1)

    flush_checks()

    local history = db_query("SELECT * FROM check_history WHERE monitor_id = ?", { id })
    spyweb.assert_eq(#history, 1)
    spyweb.assert_eq(history[1].is_up, 0)
end

function test_after_fetch_403_is_up()
    local id = make_monitor("BlockedTest", "https://blocked.example.com", true)
    local ctx = make_ctx(id)
    local fetch_result = {
        ok = true,
        response = { status = 403, url = "https://blocked.example.com" },
        request = { url = "https://blocked.example.com" },
    }

    local result = after_fetch(fetch_result, ctx)
    spyweb.assert_eq(result, nil)

    flush_status()

    local monitor = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    spyweb.assert_eq(monitor[1].is_up, 1)
    spyweb.assert_eq(monitor[1].consecutive_failures, 0)
    spyweb.assert_eq(monitor[1].last_status_code, 403)

    flush_checks()

    local history = db_query("SELECT * FROM check_history WHERE monitor_id = ?", { id })
    spyweb.assert_eq(#history, 1)
    spyweb.assert_eq(history[1].is_up, 1)
    spyweb.assert_eq(history[1].status_code, 403)
end

function test_after_fetch_handles_content_check()
    local id = make_monitor("ContentTest", "https://content.example.com", true)
    local ctx = make_ctx(id, { check_value = "expected-text", was_up = true, prev_failures = 0 })
    local fetch_result = {
        ok = true,
        response = { status = 200, url = "https://content.example.com", body = "this page has expected-text in it", time_ms = 30 },
        request = { url = "https://content.example.com" },
    }

    after_fetch(fetch_result, ctx)

    flush_status()

    local monitor = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    spyweb.assert_eq(monitor[1].is_up, 1)
end

function test_after_fetch_content_check_fails()
    local id = make_monitor("ContentFail", "https://content.example.com", true)
    local ctx = make_ctx(id, { check_value = "missing-text", was_up = true, prev_failures = 0 })
    local fetch_result = {
        ok = true,
        response = { status = 200, url = "https://content.example.com", body = "this page has no match", time_ms = 30 },
        request = { url = "https://content.example.com" },
    }

    after_fetch(fetch_result, ctx)

    flush_status()

    local monitor = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    spyweb.assert_eq(monitor[1].is_up, 0)
end

-- =============================================================================
-- treat_4xx_as_down — pipeline.run
-- =============================================================================

function test_run_403_as_down_when_setting_on()
    db.ensure_schema()
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local shared = { check_value = "", prev_failures = 0 }
    local result = check.run(
        { ok = true, response = { status = 403, time_ms = 100 } },
        shared
    )

    spyweb.assert_eq(result.is_up, 0)
    spyweb.assert_eq(result.severity, "DOWN")
    spyweb.assert_eq(result.status_code, 403)
    spyweb.assert_eq(result.new_failures, 1)
end

function test_run_500_down_regardless_of_setting()
    db.ensure_schema()
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local shared = { check_value = "", prev_failures = 0 }
    local result = check.run(
        { ok = true, response = { status = 500, time_ms = 100 } },
        shared
    )

    spyweb.assert_eq(result.is_up, 0)
    spyweb.assert_eq(result.severity, "DOWN")
end

function test_run_200_up_regardless_of_setting()
    db.ensure_schema()
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('treat_4xx_as_down', '1')")

    local shared = { check_value = "", prev_failures = 0 }
    local result = check.run(
        { ok = true, response = { status = 200, time_ms = 100 } },
        shared
    )

    spyweb.assert_eq(result.is_up, 1)
    spyweb.assert_eq(result.severity, "UP")
end

-- =============================================================================
-- Certificate threshold — per-monitor value, else the instance-wide setting
-- =============================================================================

local function set_instance_cert_threshold(value)
    db.ensure_schema()
    db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES ('cert_threshold_days', ?)", { value })
end

local function make_cert_monitor(name, url, threshold)
    db_exec("DELETE FROM monitors")
    -- 0 (the default) means inherit the instance-wide threshold
    if threshold == nil then
        threshold = 0
    end
    return db_query("INSERT INTO monitors (name, url, check_cert, cert_threshold_days) VALUES (?, ?, 1, ?) RETURNING id", { name, url, threshold })[1].id
end

local function capture_alerts()
    local alerts = {}
    alert.do_alert = function(s, severity, message)
        table.insert(alerts, message)
    end
    return alerts
end

local function stub_cert_probe(days_left)
    tls_probe = function(host)
        return {
            subject = "CN=" .. host,
            issuer = "CN=issuer",
            serial = "1",
            not_before = "",
            not_after = "",
            days_left = days_left,
            fingerprint = "fingerprint",
        }
    end
end

-- Runs one cert check for a standalone node.
local function run_cert_check(id, name, url, threshold, last_check)
    local s = {
        monitor_id = id,
        monitor_name = name,
        monitor_url = url,
        check_cert = 1,
        cert_threshold_days = threshold,
        cert_last_check = last_check,
        desktop_notify = 0,
        was_up = true,
        prev_failures = 0,
    }
    role_strategies.after_fetch("standalone", s, os.time(), {
        is_up = 1,
        status_code = 200,
        response_time_ms = 5,
        new_failures = 0,
        err_msg = "ok",
        severity = "UP",
    })
end

function test_cert_alert_uses_monitor_threshold_over_instance()
    set_instance_cert_threshold("30")
    local id = make_cert_monitor("CertOwn", "https://cert-own.example.com", 10)
    local alerts = capture_alerts()
    stub_cert_probe(20)
    -- 20 days left, monitor threshold 10: the instance-wide 30 must not apply
    run_cert_check(id, "CertOwn", "https://cert-own.example.com", 10, nil)
    spyweb.assert_eq(#alerts, 0)
end

function test_cert_alert_fires_below_monitor_threshold()
    set_instance_cert_threshold("5")
    local id = make_cert_monitor("CertSoon", "https://cert-soon.example.com", 30)
    local alerts = capture_alerts()
    stub_cert_probe(20)
    -- 20 days left, monitor threshold 30: the instance-wide 5 must not apply
    run_cert_check(id, "CertSoon", "https://cert-soon.example.com", 30, nil)
    spyweb.assert_eq(#alerts, 1)
    spyweb.assert_ne(string.find(alerts[1], "expires in 20 days"), nil)
end

-- A monitor threshold of 0 inherits the instance-wide value: 20 days left only
-- alerts because the setting says 30, not because of any hardcoded default.
function test_cert_alert_inherits_instance_threshold()
    set_instance_cert_threshold("30")
    local id = make_cert_monitor("CertInherit", "https://cert-inherit.example.com", 0)
    local alerts = capture_alerts()
    stub_cert_probe(20)
    run_cert_check(id, "CertInherit", "https://cert-inherit.example.com", 0, nil)
    spyweb.assert_eq(#alerts, 1)
end

function test_cert_alert_inherited_threshold_is_honoured()
    set_instance_cert_threshold("5")
    local id = make_cert_monitor("CertQuiet", "https://cert-quiet.example.com", 0)
    local alerts = capture_alerts()
    stub_cert_probe(20)
    run_cert_check(id, "CertQuiet", "https://cert-quiet.example.com", 0, nil)
    spyweb.assert_eq(#alerts, 0)
end

function test_cert_alert_without_instance_threshold_uses_default()
    db.ensure_schema()
    db_exec("DELETE FROM settings WHERE key = 'cert_threshold_days'")
    local id = make_cert_monitor("CertNoSetting", "https://cert-no-setting.example.com", 0)
    local alerts = capture_alerts()
    stub_cert_probe(10)
    run_cert_check(id, "CertNoSetting", "https://cert-no-setting.example.com", 0, nil)
    spyweb.assert_eq(#alerts, 1)
end

function test_cert_check_skips_within_24_hours()
    set_instance_cert_threshold("30")
    local id = make_cert_monitor("CertRecent", "https://cert-recent.example.com", 0)
    local alerts = capture_alerts()
    stub_cert_probe(1)
    run_cert_check(id, "CertRecent", "https://cert-recent.example.com", 0, os.time())
    spyweb.assert_eq(#alerts, 0)
end

-- A failed probe alerts and clears the stored certificate info.
function test_cert_probe_failure_alerts_and_clears_info()
    set_instance_cert_threshold("30")
    local id = make_cert_monitor("CertFail", "https://cert-fail.example.com", 0)
    local alerts = capture_alerts()
    tls_probe = function(host) return nil, { message = "tls handshake failed", kind = "tls" } end

    run_cert_check(id, "CertFail", "https://cert-fail.example.com", 0, nil)

    spyweb.assert_eq(#alerts, 1)
    spyweb.assert_ne(string.find(alerts[1], "TLS probe failed"), nil)
    local row = db_query("SELECT cert_not_after, cert_days_left, cert_last_check FROM monitors WHERE id = ?", { id })[1]
    spyweb.assert_eq(row.cert_not_after, "")
    spyweb.assert_eq(row.cert_days_left, 0)
    spyweb.assert_ne(row.cert_last_check, nil)
end
