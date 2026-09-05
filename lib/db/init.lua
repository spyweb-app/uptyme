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

M.first = db_first
M.build_set_clause = db_build_set_clause
M.delete_by_id = db_delete_by_id

install(require("lib.db.schema"))
install(require("lib.db.monitors"))
install(require("lib.db.settings"))
install(require("lib.db.nodes"))
install(require("lib.db.channels"))
install(require("lib.db.consensus_state"))
install(require("lib.db.status_pages"))

return M
