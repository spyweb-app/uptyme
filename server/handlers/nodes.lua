local H = require("helpers")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")
local config = require("lib.runtime_config")
local validate = require("lib.validate")

local M = {}

local function reject_non_central()
    if not config.is_central() then
        return H.json_response(403, nil, "Only central nodes can manage the node registry")
    end
    return nil
end

function M.me(self, node)
    return H.json_response(200, {
        id = node.id,
        name = node.name,
        role = node.role,
        created_at = node.created_at,
    })
end

function M.list(self)
    local denied = reject_non_central()
    if denied then return denied end

    local id = tonumber(self.path_args[1])
    if id then
        if self.query.view == "reports" then
            return H.json_response(200, db.get_node_reports(id))
        end
        local node, node_err = H.find_or_404(db.get_node, id, "Node")
        if not node then return node_err end
        node.token_hash = nil
        return H.json_response(200, node)
    end

    return H.json_response(200, db.list_nodes())
end

function M.create(self)
    local denied = reject_non_central()
    if denied then return denied end

    local data, parse_err = H.parse_body(self)
    if not data then return parse_err end

    local validated, val_err = H.validate_or_400(data, validate.node_create)
    if not validated then return val_err end

    local token = cluster_auth.generate_token()
    local prefix, secret = cluster_auth.parse_token(token)
    local hash = cluster_auth.hash_secret(secret)

    local node, db_err = db.create_node({
        name = validated.name,
        role = "checker",
        token_prefix = prefix,
        token_hash = hash,
    })
    if not node then
        return H.json_response(500, nil, "Failed to create node: " .. tostring(db_err))
    end

    return H.json_response(201, {
        node = node,
        token = token,
    })
end

function M.update(self)
    local denied = reject_non_central()
    if denied then return denied end

    local id, id_err = H.require_id(self, "Node")
    if not id then return id_err end

    if self.path_args[2] == "reset-token" then
        local node, node_err = H.find_or_404(db.get_node, id, "Node")
        if not node then return node_err end
        local token = cluster_auth.generate_token()
        local prefix, secret = cluster_auth.parse_token(token)
        local hash = cluster_auth.hash_secret(secret)
        node = db.reset_node_token(id, prefix, hash)
        node.token_hash = nil
        return H.json_response(200, { node = node, token = token })
    end

    local data, parse_err = H.parse_body(self)
    if not data then return parse_err end

    local validated, val_err = H.validate_or_400(data, validate.node_update)
    if not validated then return val_err end

    local node, node_err = H.find_or_404(db.get_node, id, "Node")
    if not node then return node_err end

    node = db.update_node(id, validated)
    if not node then
        return H.json_response(400, nil, "No fields to update")
    end
    return H.json_response(200, node)
end

function M.remove(self)
    local denied = reject_non_central()
    if denied then return denied end

    local id, id_err = H.require_id(self, "Node")
    if not id then return id_err end

    local node, node_err = H.find_or_404(db.get_node, id, "Node")
    if not node then return node_err end

    db.delete_node(id)
    return H.deleted()
end

return M
