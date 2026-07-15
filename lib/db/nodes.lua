local sha256 = require("lib.sha256")

local M = {}

function M.get_node_by_prefix(prefix)
  local rows = db_query("SELECT * FROM nodes WHERE token_prefix = ?", { prefix })
  return rows[1]
end

function M.get_node(id)
  local rows = db_query("SELECT * FROM nodes WHERE id = ?", { id })
  return rows[1]
end

function M.list_nodes()
  return db_query("SELECT * FROM nodes ORDER BY created_at DESC")
end

function M.create_node(data)
  local token = data.token or ""
  local prefix, secret = token:match("^([^%.]+)%.(.+)$")
  if not prefix or not secret then
    return nil, "invalid token format"
  end

  local ok, err = pcall(db_exec, [[
    INSERT INTO nodes (name, role, token_prefix, token_hash, active)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    data.name,
    data.role or "checker",
    prefix,
    sha256.hex(secret),
    data.active == nil and 1 or (data.active ~= 0 and 1 or 0),
  })
  if not ok then return nil, err end
  return M.get_node_by_prefix(prefix)
end

function M.touch_node(id)
  db_exec("UPDATE nodes SET last_seen_at = ?, updated_at = ? WHERE id = ?", {
    os.time(),
    os.time(),
    id,
  })
end

return M
