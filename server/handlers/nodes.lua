local H = require("helpers")
local db = require("lib.db")
local cluster_auth = require("lib.cluster_auth")
local config = require("lib.runtime_config")

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
		if self.path_args[2] == "reports" then
			return H.json_response(200, db.get_node_reports(id))
		end
		local node = db.get_node(id)
		if not node then
			return H.json_response(404, nil, "Node not found")
		end
		node.token_hash = nil
		return H.json_response(200, node)
	end
	
	return H.json_response(200, db.list_nodes())
end

function M.create(self)
	local denied = reject_non_central()
	if denied then return denied end
	
	local data = json_decode(self.body or "")
	if not data or type(data) ~= "table" then
		return H.json_response(400, nil, "Invalid JSON body")
	end
	
	if not data.name or data.name == "" then
		return H.json_response(400, nil, "name is required")
	end
	
	local token = cluster_auth.generate_token()
	local prefix, secret = cluster_auth.parse_token(token)
	local hash = cluster_auth.hash_secret(secret)

	local node, err = db.create_node({
		name = data.name,
		role = data.role or "checker",
		token_prefix = prefix,
		token_hash = hash,
	})
	if not node then
		return H.json_response(500, nil, "Failed to create node: " .. tostring(err))
	end
	
	return H.json_response(201, {
		node = node,
		token = token,
	})
end

function M.update(self)
	local denied = reject_non_central()
	if denied then return denied end
	
	local id = tonumber(self.path_args[1])
	if not id then
		return H.json_response(400, nil, "Node ID required")
	end
	
	if self.path_args[2] == "deactivate" then
		local node = db.get_node(id)
		if not node then
			return H.json_response(404, nil, "Node not found")
		end
		node = db.deactivate_node(id)
		return H.json_response(200, node)
	end
	
	if self.path_args[2] == "activate" then
		local node = db.get_node(id)
		if not node then
			return H.json_response(404, nil, "Node not found")
		end
		node = db.activate_node(id)
		return H.json_response(200, node)
	end
	
	if self.path_args[2] == "reset-token" then
		local node = db.get_node(id)
		if not node then
			return H.json_response(404, nil, "Node not found")
		end
		local token = cluster_auth.generate_token()
		local prefix, secret = cluster_auth.parse_token(token)
		local hash = cluster_auth.hash_secret(secret)
		node = db.reset_node_token(id, prefix, hash)
		node.token_hash = nil
		return H.json_response(200, { node = node, token = token })
	end
	
	local data = json_decode(self.body or "")
	if not data or type(data) ~= "table" then
		return H.json_response(400, nil, "Invalid JSON body")
	end
	
	local node = db.get_node(id)
	if not node then
		return H.json_response(404, nil, "Node not found")
	end
	
	node = db.update_node(id, data)
	return H.json_response(200, node)
end

function M.remove(self)
	local denied = reject_non_central()
	if denied then return denied end
	
	local id = H.id_or_nil(self.path_args)
	if not id then
		return H.json_response(400, nil, "Node ID required")
	end
	
	local node = db.get_node(id)
	if not node then
		return H.json_response(404, nil, "Node not found")
	end
	
	db.delete_node(id)
	return H.json_response(200, { deleted = true })
end

return M
