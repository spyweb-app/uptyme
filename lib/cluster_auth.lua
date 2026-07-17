local db = require("lib.db")
local sha256 = require("lib.sha256")

local M = {}

M.HEADER_KEY = "x-pulse-checker-token"

function M.generate_token()
    local function hex_bytes(n)
        local s = ""
        for i = 1, n do
            s = s .. string.format("%02x", math.random(0, 255))
        end
        return s
    end
    return hex_bytes(8) .. "." .. hex_bytes(32)
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
    local headers = self and self.headers or {}
    local token = headers[M.HEADER_KEY]
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
