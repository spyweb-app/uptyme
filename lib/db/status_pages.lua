local status_slug = require("lib.status_slug")

local M = {}

local function valid_type(page_type)
  return page_type == "monitor" or page_type == "group"
end

local function as_bool(value)
  return value ~= nil and value ~= 0 and value ~= false and 1 or 0
end

function M.get_status_page(id)
  return db_first("SELECT * FROM status_pages WHERE id = ?", { id })
end

function M.get_status_page_by_slug(slug)
  return db_first("SELECT * FROM status_pages WHERE slug = ?", { slug })
end

function M.list_status_pages()
  return db_query("SELECT * FROM status_pages ORDER BY type ASC, name ASC, id ASC")
end

function M.create_status_page(data)
  data = data or {}
  if not valid_type(data.type) then return nil, "invalid status page type" end
  if not data.name or data.name == "" then return nil, "name is required" end
  if data.type == "monitor" and not data.monitor_id then
    return nil, "monitor_id is required for monitor pages"
  end
  if data.type == "group" and data.monitor_id ~= nil then
    return nil, "group pages cannot have monitor_id"
  end
  if data.type == "monitor" and not db_first("SELECT id FROM monitors WHERE id = ?", { data.monitor_id }) then
    return nil, "monitor not found"
  end

  for _ = 1, 8 do
    local slug = status_slug.generate(data.name)
    local insert_sql
    local insert_params
    if data.type == "monitor" then
      insert_sql = [[
        INSERT INTO status_pages (slug, type, monitor_id, name, description, is_public)
        VALUES (?, ?, ?, ?, ?, ?)
      ]]
      insert_params = {
        slug,
        data.type,
        data.monitor_id,
        data.name,
        data.description or "",
        as_bool(data.is_public),
      }
    else
      insert_sql = [[
        INSERT INTO status_pages (slug, type, name, description, is_public)
        VALUES (?, ?, ?, ?, ?)
      ]]
      insert_params = {
        slug,
        data.type,
        data.name,
        data.description or "",
        as_bool(data.is_public),
      }
    end
    local ok, err = pcall(db_exec, insert_sql, insert_params)
    if ok then
      return db_first("SELECT * FROM status_pages WHERE slug = ?", { slug })
    end
    if err and not tostring(err):lower():match("unique") then return nil, err end
  end
  return nil, "failed to generate unique status slug"
end

function M.update_status_page(id, data)
  data = data or {}
  local page = M.get_status_page(id)
  if not page then return nil, "status page not found" end

  local sets, params = {}, {}
  if data.name ~= nil then
    if data.name == "" then return nil, "name is required" end
    sets[#sets + 1] = "name = ?"
    params[#params + 1] = data.name
  end
  if data.description ~= nil then
    sets[#sets + 1] = "description = ?"
    params[#params + 1] = data.description
  end
  if data.is_public ~= nil then
    sets[#sets + 1] = "is_public = ?"
    params[#params + 1] = as_bool(data.is_public)
  end
  if #sets == 0 then return page end

  sets[#sets + 1] = "updated_at = ?"
  params[#params + 1] = os.time()
  params[#params + 1] = id
  db_exec("UPDATE status_pages SET " .. table.concat(sets, ", ") .. " WHERE id = ?", params)
  return M.get_status_page(id)
end

function M.delete_status_page(id)
  db_exec("DELETE FROM status_page_monitors WHERE status_page_id = ?", { id })
  db_exec("DELETE FROM status_pages WHERE id = ?", { id })
end

function M.list_status_page_monitors(page_id)
  return db_query([[
    SELECT m.*, spm.display_order
    FROM status_page_monitors spm
    JOIN monitors m ON m.id = spm.monitor_id
    WHERE spm.status_page_id = ?
    ORDER BY spm.display_order ASC, m.name ASC, m.id ASC
  ]], { page_id })
end

local function require_group_page(page_id)
  local page = M.get_status_page(page_id)
  if not page then return nil, "status page not found" end
  if page.type ~= "group" then return nil, "monitor pages cannot have members" end
  return page
end

function M.add_status_page_monitor(page_id, monitor_id, display_order)
  local page, err = require_group_page(page_id)
  if not page then return nil, err end
  if not db_first("SELECT id FROM monitors WHERE id = ?", { monitor_id }) then
    return nil, "monitor not found"
  end
  local ok, insert_err = pcall(db_exec, [[
    INSERT INTO status_page_monitors (status_page_id, monitor_id, display_order)
    VALUES (?, ?, ?)
  ]], { page_id, monitor_id, tonumber(display_order) or 0 })
  if not ok then return nil, insert_err end
  return db_first("SELECT * FROM status_page_monitors WHERE status_page_id = ? AND monitor_id = ?", { page_id, monitor_id })
end

function M.update_status_page_monitor_order(page_id, monitor_id, display_order)
  local page, err = require_group_page(page_id)
  if not page then return nil, err end
  db_exec([[UPDATE status_page_monitors SET display_order = ?
    WHERE status_page_id = ? AND monitor_id = ?]], { tonumber(display_order) or 0, page_id, monitor_id })
  return db_first("SELECT * FROM status_page_monitors WHERE status_page_id = ? AND monitor_id = ?", { page_id, monitor_id })
end

function M.remove_status_page_monitor(page_id, monitor_id)
  db_exec("DELETE FROM status_page_monitors WHERE status_page_id = ? AND monitor_id = ?", { page_id, monitor_id })
end

return M
