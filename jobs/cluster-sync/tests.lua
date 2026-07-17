local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local cluster_auth = require("lib.cluster_auth")

db.ensure_schema()

local function set_bootstrap(enabled, auth_token, central_url, role)
    runtime_config.get = function()
        return {
            enabled = enabled,
            auth_token = auth_token,
            central_url = central_url,
            role = role,
        }
    end
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
    global_store_get = function()
        return "5"
    end

    local sync_called = false
    db.sync_from_central = function()
        sync_called = true
    end

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

    local store = {}
    global_store_get = function(key)
        return store[key]
    end
    global_store_set = function(key, value)
        store[key] = value
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
    spyweb.assert_eq(store.cluster_monitors_version, "7")
end
