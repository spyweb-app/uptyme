local H = require("server.tests.helpers")
local db = require("lib.db")

-- PUT /settings is throttled to 10 requests per window; these tests each PUT
-- more than once, so reset the window the same way the monitor tests do.
local function clear_settings_throttle()
    global_store_delete("ratelimit:admin:settings:update:127.0.0.1:start")
    global_store_delete("ratelimit:admin:settings:update:127.0.0.1:count")
end

local function put_settings(data)
    clear_settings_throttle()
    return http_request({
        method = "PUT",
        url = H.api("/settings"),
        body = json_encode(data),
        headers = { ["Content-Type"] = "application/json" },
    })
end

function test_update_settings_valid()
    local resp = put_settings({ retention_days = 30 })
    spyweb.assert_eq(resp.status, 200)
end

function test_update_settings_invalid_range()
    local resp = put_settings({ retention_days = 99999 })
    spyweb.assert_eq(resp.status, 400)
end

function test_update_settings_invalid_type()
    local resp = put_settings({ treat_4xx_as_down = "not a bool" })
    spyweb.assert_eq(resp.status, 400)
end

-- The Settings page serializes every field as a string. Before coercion this
-- failed the whole save with "retention_days must be a positive number".
function test_update_settings_accepts_string_numbers()
    local resp = put_settings({ retention_days = "45" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_eq(body.data.retention_days, "45")
    spyweb.assert_eq(db.get_settings().retention_days, "45")
end

-- The full payload the Settings page sends, as strings.
function test_update_settings_full_page_payload()
    local resp = put_settings({
        instance_name = "UPTYME",
        retention_days = "120",
        alert_cooldown_sec = "600",
        cert_threshold_days = "30",
        treat_4xx_as_down = "1",
        status_page_slug_style = "random",
        status_page_random_length = "7",
        status_page_name_max_length = "25",
        status_page_theme = "dark",
        consensus_min_nodes = "3",
        consensus_quorum_pct = "66",
        node_liveness_sec = "120",
    })
    spyweb.assert_eq(resp.status, 200)

    -- data must be the saved settings, not null: a swallowed write error is what
    -- made the page claim success while storing nothing.
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)
    spyweb.assert_ne(body.data, nil)

    local saved = db.get_settings()
    spyweb.assert_eq(saved.instance_name, "UPTYME")
    spyweb.assert_eq(saved.retention_days, "120")
    spyweb.assert_eq(saved.alert_cooldown_sec, "600")
    spyweb.assert_eq(saved.treat_4xx_as_down, "1")
    spyweb.assert_eq(saved.consensus_min_nodes, "3")
    spyweb.assert_eq(saved.consensus_quorum_pct, "66")
    spyweb.assert_eq(saved.node_liveness_sec, "120")
    spyweb.assert_eq(saved.status_page_theme, "dark")
    spyweb.assert_eq(saved.cert_threshold_days, "30")
    spyweb.assert_eq(saved.status_page_slug_style, "random")
    spyweb.assert_eq(saved.status_page_random_length, "7")
    spyweb.assert_eq(saved.status_page_name_max_length, "25")
end

-- Unrecognized keys are ignored so a client sending a key this build does not
-- understand still saves the rest of the form.
function test_update_settings_ignores_unknown_key()
    local resp = put_settings({ instance_name = "Renamed", totally_unknown_key = "x" })
    spyweb.assert_eq(resp.status, 200)
    local body = json_decode(resp.body)
    spyweb.assert_eq(body.success, true)

    local saved = db.get_settings()
    spyweb.assert_eq(saved.instance_name, "Renamed")
    spyweb.assert_eq(saved.totally_unknown_key, nil)
end

function test_update_settings_status_page_slug_keys_persist()
    local resp = put_settings({ status_page_slug_style = "name_random", status_page_random_length = "4", status_page_name_max_length = "10" })
    spyweb.assert_eq(resp.status, 200)

    local saved = db.get_settings()
    spyweb.assert_eq(saved.status_page_slug_style, "name_random")
    spyweb.assert_eq(saved.status_page_random_length, "4")
    spyweb.assert_eq(saved.status_page_name_max_length, "10")
end

function test_update_settings_cert_threshold_range()
    local ok = put_settings({ cert_threshold_days = "365" })
    spyweb.assert_eq(ok.status, 200)
    spyweb.assert_eq(db.get_settings().cert_threshold_days, "365")

    local too_low = put_settings({ cert_threshold_days = "0" })
    spyweb.assert_eq(too_low.status, 400)

    local too_high = put_settings({ cert_threshold_days = "366" })
    spyweb.assert_eq(too_high.status, 400)
end

function test_update_settings_rejects_bad_value_for_known_key()
    local resp = put_settings({ status_page_slug_style = "nonsense" })
    spyweb.assert_eq(resp.status, 400)
    local body = json_decode(resp.body)
    spyweb.assert_ne(string.find(body.error or "", "status_page_slug_style"), nil)
end
