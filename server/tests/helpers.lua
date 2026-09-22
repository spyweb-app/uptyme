local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")

local M = {}

function M.api(path)
    return "http://127.0.0.1:" .. SERVER_PORT .. "/api/v" .. path
end

function M.public_api(path)
    return "http://127.0.0.1:" .. SERVER_PORT .. "/api/public" .. path
end

function M.seed_two_monitors()
    db_exec("DELETE FROM monitors")
    local a = db_query("INSERT INTO monitors (name, url) VALUES ('A', 'https://a.example.com') RETURNING id")[1]
    local b = db_query("INSERT INTO monitors (name, url) VALUES ('B', 'https://b.example.com') RETURNING id")[1]
    return a.id, b.id
end

function M.make_checker_node(prefix, secret)
    local nprefix, nsecret = cluster_auth.parse_token(prefix .. "." .. secret)
    return db.create_node({ name = prefix, role = "checker", token_prefix = nprefix, token_hash = cluster_auth.hash_secret(nsecret) })
end

return M