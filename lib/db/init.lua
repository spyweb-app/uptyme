local M = {}

local function install(mod)
  for k, v in pairs(mod) do
    M[k] = v
  end
end

function db_first(sql, params)
  local rows = db_query(sql, params)
  return rows[1]
end

function db_build_set_clause(data, allowed_fields)
  local sets = {}
  local params = {}
  for _, field in ipairs(allowed_fields) do
    if data[field] ~= nil then
      table.insert(sets, field .. " = ?")
      table.insert(params, data[field])
    end
  end
  return sets, params
end

function db_delete_by_id(table_name, id)
  db_exec("DELETE FROM " .. table_name .. " WHERE id = ?", { id })
end

function db_select_one(table_name, fields, key, value)
  return db_first("SELECT " .. fields .. " FROM " .. table_name .. " WHERE " .. key .. " = ?", { value })
end

function db_update_by_id(table_name, id, data, allowlist, opts)
  opts = opts or {}
  local sets, params = db_build_set_clause(data, allowlist)
  if #sets == 0 then return nil, "no fields to update" end
  if opts.updated_at then
    sets[#sets + 1] = "updated_at = ?"
    params[#params + 1] = os.time()
  end
  local key = opts.key or "id"
  params[#params + 1] = id
  return db_exec("UPDATE " .. table_name .. " SET " .. table.concat(sets, ", ") .. " WHERE " .. key .. " = ?", params)
end

M.first = db_first
M.build_set_clause = db_build_set_clause
M.delete_by_id = db_delete_by_id
M.select_one = db_select_one
M.update_by_id = db_update_by_id

install(require("lib.db.schema"))
install(require("lib.db.monitors"))
install(require("lib.db.settings"))
install(require("lib.db.nodes"))
install(require("lib.db.channels"))
install(require("lib.db.consensus_state"))
install(require("lib.db.status_pages"))
install(require("lib.db.public_status"))

return M
