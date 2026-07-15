local db = require("lib.db")
local sha256 = require("lib.sha256")

local M = {}

local HEADER = "x-pulse-checker-token"

local function get_header(self)
    local headers = self and self.headers or {}
    return headers[HEADER] or headers["X-Pulse-Checker-Token"] or headers["X-PULSE-CHECKER-TOKEN"]
end

function M.parse_token(token)
    if not token or token == "" then
        return nil, nil
    end
    local prefix, secret = token:match("^([^%.]+)%.(.+)$")
    if not prefix or not secret then
        return nil, nil
    end
    return prefix, secret
end

function M.hash_secret(secret)
    return sha256.digest(secret or "")
end

function M.verify(self)
    local token = get_header(self)
    if not token or token == "" then
        return nil
    end

    local prefix, secret = M.parse_token(token)
    if not prefix or not secret then
        return nil
    end

    local node = db.get_node_by_prefix(prefix)
    if not node or node.active ~= 1 then
        return nil
    end

    if not sha256.equal(node.token_hash or "", M.hash_secret(secret)) then
        return nil
    end

    db.touch_node(node.id)
    return node
end

return M
