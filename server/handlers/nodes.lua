local H = require("helpers")
local cluster_auth = require("lib.cluster_auth")

local M = {}

function M.me(self)
  local node = cluster_auth.verify(self)
  if not node then
    return H.json_response(401, nil, "Unauthorized")
  end

  return H.json_response(200, {
    id = node.id,
    name = node.name,
    role = node.role,
    created_at = node.created_at,
  })
end

return M
