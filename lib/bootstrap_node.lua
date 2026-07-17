local db = require("lib.db")
local runtime_config = require("lib.runtime_config")
local cluster_auth = require("lib.cluster_auth")

local M = {}

function M.bootstrap()
  local s = db.get_settings()
  if s.cluster_node_id then return end

  local cfg = runtime_config.get()
  if (cfg.role or "standalone") ~= "checker" then return end

  local url = (cfg.central_url or "") .. "/api/public/node/me"
  local token = cfg.auth_token or ""
  if url == "" or token == "" then
    return
  end

  local headers = { [cluster_auth.HEADER_KEY] = token }
  local resp, err = http_get(url, headers)
  if not resp then
    return
  end

  local data = json_decode(resp.body)
  if not data or not data.success or not data.data then
    return
  end

  db.update_settings({
    cluster_node_id = tostring(data.data.id),
    cluster_node_name = data.data.name,
  })
  log("Bootstrapped as node: " .. data.data.name .. " (id=" .. data.data.id .. ")")
end

return M
