local validate = require("lib.validate")

function test_settings_update_coerces_string_numbers()
    local out = validate.settings_update({
        retention_days = "30",
        alert_cooldown_sec = "120",
        node_liveness_sec = "60",
        consensus_min_nodes = "3",
        consensus_quorum_pct = "66",
        cert_threshold_days = "45",
        status_page_random_length = "7",
        status_page_name_max_length = "25",
    })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.retention_days, 30)
    spyweb.assert_eq(out.alert_cooldown_sec, 120)
    spyweb.assert_eq(out.node_liveness_sec, 60)
    spyweb.assert_eq(out.consensus_min_nodes, 3)
    spyweb.assert_eq(out.consensus_quorum_pct, 66)
    spyweb.assert_eq(out.cert_threshold_days, 45)
    spyweb.assert_eq(out.status_page_random_length, 7)
    spyweb.assert_eq(out.status_page_name_max_length, 25)
end

function test_settings_update_coerces_booleans()
    spyweb.assert_eq(validate.settings_update({ treat_4xx_as_down = "1" }).treat_4xx_as_down, 1)
    spyweb.assert_eq(validate.settings_update({ treat_4xx_as_down = "0" }).treat_4xx_as_down, 0)
    spyweb.assert_eq(validate.settings_update({ treat_4xx_as_down = true }).treat_4xx_as_down, 1)
    spyweb.assert_eq(validate.settings_update({ treat_4xx_as_down = 0 }).treat_4xx_as_down, 0)
end

function test_settings_update_rejects_uncoercible_boolean()
    local out, err = validate.settings_update({ treat_4xx_as_down = "yes" })
    spyweb.assert_eq(out, nil)
    spyweb.assert_ne(string.find(err or "", "treat_4xx_as_down"), nil)
end

function test_settings_update_ignores_unknown_keys()
    local out = validate.settings_update({ instance_name = "Renamed", bogus = "x", unrelated = 5 })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.instance_name, "Renamed")
    spyweb.assert_eq(out.bogus, nil)
    spyweb.assert_eq(out.unrelated, nil)
end

function test_settings_update_returns_only_known_keys()
    local out = validate.settings_update({ status_page_theme = "dark", nope = "1" })
    local count = 0
    for _ in pairs(out) do count = count + 1 end
    spyweb.assert_eq(count, 1)
    spyweb.assert_eq(out.status_page_theme, "dark")
end

function test_settings_update_rejects_non_numeric_number()
    local out, err = validate.settings_update({ retention_days = "abc" })
    spyweb.assert_eq(out, nil)
    spyweb.assert_ne(string.find(err or "", "retention_days"), nil)
end

function test_settings_update_rejects_hex_and_float()
    spyweb.assert_eq(validate.settings_update({ retention_days = "0x10" }), nil)
    spyweb.assert_eq(validate.settings_update({ retention_days = "30.5" }), nil)
    spyweb.assert_eq(validate.settings_update({ retention_days = " 30 " }), nil)
end

function test_settings_update_coerces_free_text()
    local out = validate.settings_update({ instance_name = 123 })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.instance_name, "123")
end

function test_settings_update_rejects_non_string_free_text()
    spyweb.assert_eq(validate.settings_update({ instance_name = true }), nil)
end

function test_settings_update_enforces_ranges()
    spyweb.assert_eq(validate.settings_update({ cert_threshold_days = "365" }).cert_threshold_days, 365)
    spyweb.assert_eq(validate.settings_update({ cert_threshold_days = "0" }), nil)
    spyweb.assert_eq(validate.settings_update({ cert_threshold_days = "366" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_random_length = "2" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_random_length = "11" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_name_max_length = "4" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_name_max_length = "51" }), nil)
    spyweb.assert_eq(validate.settings_update({ alert_cooldown_sec = "59" }), nil)
end

function test_settings_update_rejects_bad_enums()
    spyweb.assert_eq(validate.settings_update({ status_page_theme = "blue" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_slug_style = "weird" }), nil)
    spyweb.assert_eq(validate.settings_update({ status_page_slug_style = "random" }).status_page_slug_style, "random")
end

-- ─── Monitor ─────────────────────────────────────────────────

function test_monitor_create_coerces_types()
    local out = validate.monitor_create({
        name = "Coerced",
        url = "https://coerced.example.com",
        interval_sec = "60",
        timeout_ms = "5000",
        cert_threshold_days = "30",
        check_cert = "1",
        enabled = "0",
        desktop_notify = "1",
    })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.interval_sec, 60)
    spyweb.assert_eq(out.timeout_ms, 5000)
    spyweb.assert_eq(out.cert_threshold_days, 30)
    spyweb.assert_eq(out.check_cert, 1)
    spyweb.assert_eq(out.enabled, 0)
    spyweb.assert_eq(out.desktop_notify, 1)
end

-- A monitor with no threshold defaults to 0, which inherits the instance-wide
-- value at check time.
function test_monitor_create_defaults_threshold_to_zero()
    local out = validate.monitor_create({ name = "Inherit", url = "https://inherit.example.com", check_cert = 1 })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.cert_threshold_days, 0)
end

function test_monitor_create_rejects_number_url()
    local out, err = validate.monitor_create({ name = "Bad", url = 123 })
    spyweb.assert_eq(out, nil)
    spyweb.assert_ne(string.find(err or "", "url"), nil)
end

-- check_value is free text: a bare number is coerced instead of raising.
function test_monitor_create_coerces_check_value()
    local out = validate.monitor_create({
        name = "Content",
        url = "https://content.example.com",
        check_value = 12345,
    })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.check_value, "12345")
end

function test_monitor_create_rejects_hex_interval()
    spyweb.assert_eq(validate.monitor_create({ name = "H", url = "https://h.example.com", interval_sec = "0x10" }), nil)
end

function test_monitor_create_rejects_uncoercible_boolean()
    spyweb.assert_eq(validate.monitor_create({ name = "B", url = "https://b.example.com", enabled = "sometimes" }), nil)
end

function test_monitor_update_coerces_numbers()
    local out = validate.monitor_update({ name = "New", interval_sec = "90", cert_threshold_days = "20" })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.name, "New")
    spyweb.assert_eq(out.interval_sec, 90)
    spyweb.assert_eq(out.cert_threshold_days, 20)
end

function test_monitor_update_rejects_bad_cert_range()
    spyweb.assert_eq(validate.monitor_update({ cert_threshold_days = "-1" }), nil)
    spyweb.assert_eq(validate.monitor_update({ cert_threshold_days = "366" }), nil)
    spyweb.assert_eq(validate.monitor_update({ cert_threshold_days = "0" }).cert_threshold_days, 0)
end

-- ─── Channel ─────────────────────────────────────────────────

function test_channel_create_coerces_enabled()
    local out = validate.channel_create({
        name = "Hook",
        type = "webhook",
        config = '{"url":"https://hook.example.com"}',
        enabled = "1",
    })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.enabled, 1)
end

function test_channel_create_rejects_uncoercible_enabled()
    local out = validate.channel_create({
        name = "Hook",
        type = "webhook",
        config = '{"url":"https://hook.example.com"}',
        enabled = "yes",
    })
    spyweb.assert_eq(out, nil)
end

function test_channel_create_rejects_number_config()
    spyweb.assert_eq(validate.channel_create({ name = "Hook", type = "webhook", config = 123 }), nil)
end

-- ─── Node ────────────────────────────────────────────────────

function test_node_create_coerces_name()
    local out = validate.node_create({ name = 42 })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.name, "42")
end

-- ─── Status page ─────────────────────────────────────────────

function test_status_page_create_coerces_types()
    local out = validate.status_page_create({ type = "group", name = "Page", is_public = "1" })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.is_public, 1)

    local monitor_page = validate.status_page_create({ type = "monitor", name = "One", monitor_id = "5" })
    spyweb.assert_ne(monitor_page, nil)
    spyweb.assert_eq(monitor_page.monitor_id, 5)
end

function test_status_page_create_requires_monitor_id()
    local out, err = validate.status_page_create({ type = "monitor", name = "One" })
    spyweb.assert_eq(out, nil)
    spyweb.assert_ne(string.find(err or "", "monitor_id"), nil)
end

function test_status_page_update_coerces_is_public()
    local out = validate.status_page_update({ is_public = "0" })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.is_public, 0)
end

-- ─── Report ──────────────────────────────────────────────────

function test_report_payload_coerces_types()
    local out = validate.report_payload({
        reports = { { monitor_id = "5", is_up = "1", status_code = "200", response_time_ms = "12" } },
    })
    spyweb.assert_ne(out, nil)
    spyweb.assert_eq(out.reports[1].monitor_id, 5)
    spyweb.assert_eq(out.reports[1].is_up, 1)
    spyweb.assert_eq(out.reports[1].status_code, 200)
    spyweb.assert_eq(out.reports[1].response_time_ms, 12)
end

function test_report_payload_rejects_non_numeric_monitor_id()
    local out, err = validate.report_payload({ reports = { { monitor_id = "abc", is_up = 1 } } })
    spyweb.assert_eq(out, nil)
    spyweb.assert_ne(string.find(err or "", "monitor_id"), nil)
end

function test_report_payload_requires_is_up()
    spyweb.assert_eq(validate.report_payload({ reports = { { monitor_id = 1 } } }), nil)
end

function test_report_payload_rejects_non_object_entry()
    spyweb.assert_eq(validate.report_payload({ reports = { "nope" } }), nil)
end

function test_report_payload_rejects_oversized_batch()
    local reports = {}
    for i = 1, 101 do reports[i] = { monitor_id = i, is_up = 1 } end
    spyweb.assert_eq(validate.report_payload({ reports = reports }), nil)
end
