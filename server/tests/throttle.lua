local H = require("server.tests.helpers")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")
local rate_limit = require("lib.rate_limit")

local function clear_counter(key)
    global_store_delete("ratelimit:" .. key .. ":start")
    global_store_delete("ratelimit:" .. key .. ":count")
end

local function insert_monitor(name)
    local row = db_query(
        "INSERT INTO monitors (name, url) VALUES (?, ?) RETURNING id",
        { name, "https://" .. name .. ".example.com" }
    )[1]
    return row.id
end

local function report_request(token, monitor_id, client_ip)
    return public.post.report({
        client_ip = client_ip,
        headers = {
            [cluster_auth.HEADER_KEY] = token,
            ["Content-Type"] = "application/json",
        },
        body = json_encode({
            reports = { { monitor_id = monitor_id, is_up = 1 } },
        }),
    })
end

function test_throttle_allows_within_limit()
    local key = "test:throttle:allows"
    clear_counter(key)

    spyweb.assert_eq(rate_limit.check(key, 2, 60), nil)
    spyweb.assert_eq(rate_limit.check(key, 2, 60), nil)
    spyweb.assert_ne(rate_limit.check(key, 2, 60), nil)

    clear_counter(key)
end

function test_throttle_blocks_over_limit_with_metadata()
    local key = "test:throttle:metadata"
    clear_counter(key)

    rate_limit.check(key, 1, 60)
    local err = rate_limit.check(key, 1, 60)

    spyweb.assert_ne(err, nil)
    spyweb.assert_eq(err.limit, 1)
    spyweb.assert_eq(err.remaining, 0)
    spyweb.assert_eq(type(err.retry_after), "number")

    clear_counter(key)
end

function test_throttle_resets_after_window_boundary()
    local key = "test:throttle:reset"
    clear_counter(key)

    global_store_set("ratelimit:" .. key .. ":start", tostring(os.time() - 120))
    global_store_set("ratelimit:" .. key .. ":count", "99")

    spyweb.assert_eq(rate_limit.check(key, 1, 60), nil)
    spyweb.assert_eq(global_store_get("ratelimit:" .. key .. ":count"), "1")

    clear_counter(key)
end

function test_throttle_independent_scopes()
    local first = "test:throttle:scope:first"
    local second = "test:throttle:scope:second"
    clear_counter(first)
    clear_counter(second)

    rate_limit.check(first, 1, 60)
    spyweb.assert_ne(rate_limit.check(first, 1, 60), nil)
    spyweb.assert_eq(rate_limit.check(second, 1, 60), nil)

    clear_counter(first)
    clear_counter(second)
end

function test_public_throttle_returns_429_headers()
    local key = "public:cluster-version:198.51.100.10"
    clear_counter(key)

    local request = {
        client_ip = "198.51.100.10:54321",
        headers = {},
    }
    for _ = 1, 30 do
        spyweb.assert_eq(public.get.cluster_version(request).status, 401)
    end

    local response = public.get.cluster_version(request)
    spyweb.assert_eq(response.status, 429)
    spyweb.assert_eq(response.headers["Retry-After"] ~= nil, true)
    spyweb.assert_eq(response.headers["X-RateLimit-Limit"], "30")
    spyweb.assert_eq(response.headers["X-RateLimit-Remaining"], "0")

    clear_counter(key)
end

function test_throttle_forwards_authenticated_node_argument()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local monitor_id = insert_monitor("throttle-forward")
    local node = H.make_checker_node("throttle-forward-node", "secret")
    local response = report_request(
        "throttle-forward-node.secret",
        monitor_id,
        "198.51.100.11:54321"
    )

    spyweb.assert_eq(response.status, 200)
    spyweb.assert_ne(node, nil)
end

function test_report_throttle_scopes_by_node_for_shared_ip()
    db_exec("DELETE FROM nodes")
    db_exec("DELETE FROM monitors")

    local monitor_id = insert_monitor("throttle-node-scope")
    local first = H.make_checker_node("throttle-node-a", "secret-a")
    local second = H.make_checker_node("throttle-node-b", "secret-b")
    local client_ip = "198.51.100.12:54321"

    spyweb.assert_eq(report_request("throttle-node-a.secret-a", monitor_id, client_ip).status, 200)
    spyweb.assert_eq(report_request("throttle-node-b.secret-b", monitor_id, client_ip).status, 200)

    spyweb.assert_eq(global_store_get("ratelimit:public:report:node:" .. first.id .. ":count"), "1")
    spyweb.assert_eq(global_store_get("ratelimit:public:report:node:" .. second.id .. ":count"), "1")
    spyweb.assert_eq(global_store_get("ratelimit:public:report:ip:198.51.100.12:count"), "2")

    clear_counter("public:report:node:" .. first.id)
    clear_counter("public:report:node:" .. second.id)
    clear_counter("public:report:ip:198.51.100.12")
end
