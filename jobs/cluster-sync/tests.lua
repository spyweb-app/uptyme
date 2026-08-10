local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local cluster_auth = require("lib.cluster_auth")

db.ensure_schema()

local NO_LOGGING = { level = "error", output = "none", throttle = 0 }

local function set_bootstrap(enabled, auth_token, central_url, role)
    runtime_config.get = function()
        return {
            enabled = enabled,
            auth_token = auth_token,
            central_url = central_url,
            role = role,
        }
    end
    runtime_config.logging = function() return NO_LOGGING end
end

local function stub_http_get(sequence)
    local calls = {}
    http_get = function(url, headers)
        calls[#calls + 1] = { url = url, headers = headers }
        local item = table.remove(sequence, 1)
        if not item then
            return nil, { message = "unexpected call" }
        end
        return item.resp, item.err
    end
    return calls
end

local function stub_notify()
    local calls = {}
    local orig = notify
    notify = function(title, body, timeout_ms)
        calls[#calls + 1] = { title = title, body = body, timeout_ms = timeout_ms }
    end
    return calls, function() notify = orig end
end

local function stub_logger()
    local file_lines = {}
    local term_lines = {}
    local orig_log = log
    local orig_print = print
    log = function(msg) file_lines[#file_lines + 1] = msg end
    print = function(msg) term_lines[#term_lines + 1] = msg end
    return file_lines, term_lines, function()
        log = orig_log
        print = orig_print
    end
end

function test_before_fetch_noop_when_not_checker()
    db.update_settings({ role = "standalone" })
    set_bootstrap(false, nil, nil)

    local sync_called = false
    db.sync_from_central = function()
        sync_called = true
    end

    local result = before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(result, nil)
    spyweb.assert_eq(sync_called, false)
end

function test_before_fetch_noop_when_version_matches()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")

    local sync_called = false
    db.sync_from_central = function()
        sync_called = true
    end

    -- Prime the cache with version "5"
    stub_http_get({
        { resp = { body = "5" } },
        { resp = { body = json_encode({}) } },
    })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    -- Now call with same version → cache hit
    sync_called = false
    stub_http_get({
        { resp = { body = "5" } },
    })
    local result = before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(result, nil)
    spyweb.assert_eq(sync_called, false)
end

function test_before_fetch_syncs_when_version_changes()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")

    local seen_rows
    db.sync_from_central = function(rows)
        seen_rows = rows
    end

    local calls = stub_http_get({
        { resp = { body = "7" } },
        { resp = { body = json_encode({
            {
                id = 11,
                name = "Central Monitor",
                url = "https://example.com",
                method = "HEAD",
                interval_sec = 60,
                timeout_ms = 1000,
                check_value = "",
                enabled = 1,
                desktop_notify = 0,
                check_cert = 0,
                cert_threshold_days = 14,
            }
        }) } },
    })

    local result = before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(result, nil)
    spyweb.assert_eq(#calls, 2)
    spyweb.assert_eq(calls[1].url, "https://central.example.com/api/public/cluster_version")
    spyweb.assert_eq(calls[2].url, "https://central.example.com/api/public/cluster_export")
    spyweb.assert_eq(calls[1].headers[cluster_auth.HEADER_KEY], "node1.secret")
    spyweb.assert_eq(calls[2].headers[cluster_auth.HEADER_KEY], "node1.secret")
    spyweb.assert_ne(seen_rows, nil)
    spyweb.assert_eq(seen_rows[1].id, 11)
end

-- sync_from_central integration tests

function test_sync_creates_new_monitors()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db.sync_from_central({
        { id = 201, name = "Alpha", url = "https://alpha.com" },
        { id = 202, name = "Beta", url = "https://beta.com", method = "GET", interval_sec = 60, timeout_ms = 5000, check_cert = 1, cert_threshold_days = 30 },
    })

    local a = db.get(201)
    spyweb.assert_ne(a, nil)
    spyweb.assert_eq(a.name, "Alpha")
    spyweb.assert_eq(a.url, "https://alpha.com")
    spyweb.assert_eq(a.method, "HEAD")
    spyweb.assert_eq(a.interval_sec, 300)
    spyweb.assert_eq(a.timeout_ms, 10000)
    spyweb.assert_eq(a.check_value, "")
    spyweb.assert_eq(a.enabled, 1)

    local b = db.get(202)
    spyweb.assert_ne(b, nil)
    spyweb.assert_eq(b.name, "Beta")
    spyweb.assert_eq(b.url, "https://beta.com")
    spyweb.assert_eq(b.method, "GET")
    spyweb.assert_eq(b.interval_sec, 60)
    spyweb.assert_eq(b.timeout_ms, 5000)
    spyweb.assert_eq(b.check_cert, 1)
    spyweb.assert_eq(b.cert_threshold_days, 30)
end

function test_sync_updates_existing_monitor()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db_exec("INSERT INTO monitors (id, name, url, interval_sec, is_up, consecutive_failures, last_status_code, last_response_time_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        { 301, "Old Name", "https://old.com", 60, 0, 3, 500, 1200 })

    db.sync_from_central({
        { id = 301, name = "New Name", url = "https://new.com", interval_sec = 120, timeout_ms = 8000, enabled = 1 },
    })

    local m = db.get(301)
    spyweb.assert_eq(m.name, "New Name")
    spyweb.assert_eq(m.url, "https://new.com")
    spyweb.assert_eq(m.interval_sec, 120)
    spyweb.assert_eq(m.timeout_ms, 8000)
    spyweb.assert_eq(m.is_up, 0)
    spyweb.assert_eq(m.consecutive_failures, 3)
    spyweb.assert_eq(m.last_status_code, 500)
    spyweb.assert_eq(m.last_response_time_ms, 1200)
end

function test_sync_disables_removed_monitors()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db_exec("INSERT INTO monitors (id, name, url, enabled) VALUES (?, ?, ?, 1)", { 401, "Keep", "https://keep.com" })
    db_exec("INSERT INTO monitors (id, name, url, enabled) VALUES (?, ?, ?, 1)", { 402, "Remove", "https://remove.com" })
    db_exec("INSERT INTO monitors (id, name, url, enabled) VALUES (?, ?, ?, 1)", { 403, "Also Keep", "https://keep2.com" })

    db.sync_from_central({
        { id = 401, name = "Keep", url = "https://keep.com" },
        { id = 403, name = "Also Keep", url = "https://keep2.com" },
    })

    spyweb.assert_eq(db.get(401).enabled, 1)
    spyweb.assert_eq(db.get(403).enabled, 1)
    spyweb.assert_eq(db.get(402).enabled, 0)
end

function test_sync_reattaches_disabled_monitor()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db_exec("INSERT INTO monitors (id, name, url, enabled) VALUES (?, ?, ?, 0)", { 501, "Was Off", "https://was-off.com" })

    db.sync_from_central({
        { id = 501, name = "Was Off", url = "https://was-off.com" },
    })

    spyweb.assert_eq(db.get(501).enabled, 1)
end

function test_sync_handles_empty_rows()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db.sync_from_central({})
    spyweb.assert_eq(#db_query("SELECT * FROM monitors"), 0)

    db.sync_from_central(nil)
    spyweb.assert_eq(#db_query("SELECT * FROM monitors"), 0)
end

function test_sync_skips_invalid_entries()
    local mod = require("lib.db.monitors")
    db.sync_from_central = mod.sync_from_central
    db_exec("DELETE FROM monitors")

    db.sync_from_central({
        { id = nil, name = "No ID", url = "https://noid.com" },
        { id = 602, name = "", url = "https://noname.com" },
        { id = 603, name = "No URL", url = "" },
        { id = nil, name = nil, url = nil },
    })

    -- Only nil id/name/url are skipped; empty strings are truthy in Lua
    local all = db_query("SELECT * FROM monitors")
    spyweb.assert_eq(#all, 2)
end

-- Connectivity alert tests

function test_connectivity_down_after_threshold()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    local calls, restore = stub_notify()

    -- Two failures: not yet
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(#calls, 0)

    -- Third failure: down
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(#calls, 1)
    spyweb.assert_eq(calls[1].title, "DOWN: Central")

    restore()
end

function test_connectivity_reset_on_success_after_down()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    local calls, restore = stub_notify()

    -- Trigger down
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(#calls, 1)
    spyweb.assert_eq(calls[1].title, "DOWN: Central")

    -- Success → up
    stub_http_get({ { resp = { body = "10" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(#calls, 2)
    spyweb.assert_eq(calls[2].title, "UP: Central")

    restore()
end

function test_connectivity_no_double_down_event()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 3,
            checker_alerts = {
                channels = { { type = "ntfy", config = { url = "https://ntfy.sh", topic = "test" } } },
            },
        }
    end
    runtime_config.logging = function() return NO_LOGGING end

    local notifications = {}
    local notifier = require("lib.notifier")
    local orig_dispatch_config = notifier.dispatch_config
    notifier.dispatch_config = function(channels, alert)
        notifications[#notifications + 1] = alert
    end
    local notify_calls, restore_notify = stub_notify()

    -- 4 failures: down event only on the 3rd
    for i = 1, 4 do
        stub_http_get({ { resp = nil, err = { message = "timeout" } } })
        before_fetch({ url = "", headers = {} }, { shared = {} })
    end

    -- Should only have one down notification via channels
    local down_count = 0
    for _, n in ipairs(notifications) do
        if n.severity == "DOWN" then down_count = down_count + 1 end
    end
    spyweb.assert_eq(down_count, 1)

    -- And exactly one desktop DOWN notification
    local desktop_down = 0
    for _, c in ipairs(notify_calls) do
        if c.title == "DOWN: Central" then desktop_down = desktop_down + 1 end
    end
    spyweb.assert_eq(desktop_down, 1)

    notifier.dispatch_config = orig_dispatch_config
    restore_notify()
end

function test_connectivity_threshold_respects_config()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 1,
        }
    end
    runtime_config.logging = function() return NO_LOGGING end
    local calls, restore = stub_notify()

    -- Single failure: down (threshold=1)
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    spyweb.assert_eq(#calls, 1)
    spyweb.assert_eq(calls[1].title, "DOWN: Central")

    restore()
end

function test_connectivity_dispatches_on_down_and_up()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 3,
            checker_alerts = {
                channels = { { type = "ntfy", config = { url = "https://ntfy.sh", topic = "test" } } },
            },
        }
    end
    runtime_config.logging = function() return NO_LOGGING end

    local notifications = {}
    local notifier = require("lib.notifier")
    local orig_dispatch_config = notifier.dispatch_config
    notifier.dispatch_config = function(channels, alert)
        notifications[#notifications + 1] = alert
    end
    local notify_calls, restore_notify = stub_notify()

    -- Trigger down
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    -- Success → up
    stub_http_get({ { resp = { body = "10" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    spyweb.assert_eq(#notifications, 2)
    spyweb.assert_eq(notifications[1].severity, "DOWN")
    spyweb.assert_eq(notifications[2].severity, "UP")
    spyweb.assert_eq(#notify_calls, 2)
    spyweb.assert_eq(notify_calls[1].title, "DOWN: Central")
    spyweb.assert_eq(notify_calls[2].title, "UP: Central")

    notifier.dispatch_config = orig_dispatch_config
    restore_notify()
end

function test_connectivity_no_notification_without_channels()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 1,
        }
    end
    runtime_config.logging = function() return NO_LOGGING end

    local notifications = {}
    local notifier = require("lib.notifier")
    local orig_dispatch_config = notifier.dispatch_config
    notifier.dispatch_config = function(channels, alert)
        notifications[#notifications + 1] = alert
    end
    local notify_calls, restore_notify = stub_notify()

    -- Single failure → down event but no channel notification (no channels)
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    spyweb.assert_eq(#notifications, 0)
    spyweb.assert_eq(#notify_calls, 1)
    spyweb.assert_eq(notify_calls[1].title, "DOWN: Central")

    notifier.dispatch_config = orig_dispatch_config
    restore_notify()
end

function test_connectivity_desktop_fires_on_down_and_up()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 3,
            checker_alerts = { desktop = true },
        }
    end
    runtime_config.logging = function() return NO_LOGGING end
    local calls, restore = stub_notify()

    -- Trigger down
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    -- Success → up
    stub_http_get({ { resp = { body = "10" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    spyweb.assert_eq(#calls, 2)
    spyweb.assert_eq(calls[1].title, "DOWN: Central")
    spyweb.assert_eq(calls[2].title, "UP: Central")

    restore()
end

function test_connectivity_desktop_default_true_when_absent()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 1,
            checker_alerts = {},
        }
    end
    runtime_config.logging = function() return NO_LOGGING end
    local calls, restore = stub_notify()

    -- Single failure → down, desktop fires by default
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    spyweb.assert_eq(#calls, 1)
    spyweb.assert_eq(calls[1].title, "DOWN: Central")

    restore()
end

function test_connectivity_desktop_suppressed_when_false()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 1,
            checker_alerts = { desktop = false },
        }
    end
    runtime_config.logging = function() return NO_LOGGING end
    local calls, restore = stub_notify()

    -- Single failure → down, desktop suppressed
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    spyweb.assert_eq(#calls, 0)

    restore()
end

-- Logger tests

function test_logger_level_gate()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
        }
    end
    runtime_config.logging = function() return { level = "error", output = "both", throttle = 0 } end

    local file_lines, term_lines, restore = stub_logger()

    local logger = require("lib.logger")
    logger.debug("debug msg", "test")
    logger.info("info msg", "test")
    logger.warn("warn msg", "test")
    logger.error("error msg", "test")

    spyweb.assert_eq(#file_lines, 1)
    spyweb.assert_eq(file_lines[1], "error msg")
    spyweb.assert_eq(#term_lines, 1)
    spyweb.assert_eq(term_lines[1], "error msg")

    restore()
end

function test_logger_output_none_suppresses_all()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
        }
    end
    runtime_config.logging = function() return { level = "debug", output = "none", throttle = 0 } end

    local file_lines, _, restore = stub_logger()

    local logger = require("lib.logger")
    logger.error("should not appear", "test")

    spyweb.assert_eq(#file_lines, 0)

    restore()
end

function test_logger_err_msg_renders_tables()
    local logger = require("lib.logger")
    spyweb.assert_eq(logger.err_msg("plain string"), "plain string")
    spyweb.assert_eq(logger.err_msg({ message = "msg field" }), "msg field")
    spyweb.assert_eq(logger.err_msg({ error = "err field" }), "err field")
    spyweb.assert_eq(logger.err_msg(nil), "nil")
end

function test_logger_throttle_suppresses_repeats()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
        }
    end
    runtime_config.logging = function() return { level = "error", output = "both", throttle = 2 } end

    local file_lines, _, restore = stub_logger()

    local logger = require("lib.logger")
    logger._reset()
    logger.error("fail", "cat.throttle")
    logger.error("fail", "cat.throttle")
    logger.error("fail", "cat.throttle")
    logger.error("fail", "cat.throttle")

    -- 1st logged, 2nd-3rd suppressed (throttle=2), 4th logs again with suppressed count
    spyweb.assert_eq(#file_lines, 2)
    spyweb.assert_eq(file_lines[1], "fail")
    spyweb.assert_eq(file_lines[2], "fail (2 suppressed)")

    restore()
end

function test_logger_throttle_ignores_different_categories()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
        }
    end
    runtime_config.logging = function() return { level = "error", output = "both", throttle = 1 } end

    local file_lines, _, restore = stub_logger()

    local logger = require("lib.logger")
    logger._reset()
    logger.error("fail a", "cat.a")
    logger.error("fail a", "cat.a")
    logger.error("fail a", "cat.a")
    logger.error("fail b", "cat.b")

    spyweb.assert_eq(#file_lines, 3)
    spyweb.assert_eq(file_lines[1], "fail a")
    spyweb.assert_eq(file_lines[2], "fail a (1 suppressed)")
    spyweb.assert_eq(file_lines[3], "fail b")

    restore()
end

function test_logger_connectivity_transition_logging()
    set_bootstrap(true, "node1.secret", "https://central.example.com", "checker")
    runtime_config.get = function()
        return {
            enabled = true,
            auth_token = "node1.secret",
            central_url = "https://central.example.com",
            role = "checker",
            central_alert_failures = 3,
            checker_alerts = { desktop = false },
        }
    end
    runtime_config.logging = function() return { level = "info", output = "both", throttle = 0 } end

    local file_lines, _, restore = stub_logger()

    -- 3 failures
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })
    stub_http_get({ { resp = nil, err = { message = "timeout" } } })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    -- success (version + export)
    stub_http_get({
        { resp = { body = "10" } },
        { resp = { body = json_encode({}) } },
    })
    before_fetch({ url = "", headers = {} }, { shared = {} })

    -- warn on 1st, error on down, info on up
    spyweb.assert_eq(#file_lines, 3)
    spyweb.assert_eq(file_lines[1], "central unreachable, first failure — timeout")
    spyweb.assert_eq(file_lines[2], "Central unreachable — https://central.example.com (after 3 consecutive failures)")
    spyweb.assert_eq(file_lines[3], "Central connection restored — https://central.example.com")

    restore()
end
