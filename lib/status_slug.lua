local settings = require("lib.db.settings")

local ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"

local function random_suffix(length)
  local out = {}
  for i = 1, length do
    local index = math.random(1, #ALPHABET)
    out[i] = ALPHABET:sub(index, index)
  end
  return table.concat(out)
end

local function slugify(name, max_length)
  local value = (name or ""):lower():gsub("[^a-z0-9]+", "-")
  value = value:gsub("^%-+", ""):gsub("%-+$", "")
  if #value > max_length then
    value = value:sub(1, max_length):gsub("%-+$", "")
  end
  return value
end

local M = {}

function M.generate(name)
  local slug_style = settings.get_setting("status_page_slug_style", "name_random")
  local random_length = settings.get_int("status_page_random_length", 5)
  local name_max_length = settings.get_int("status_page_name_max_length", 20)
  local suffix = random_suffix(random_length)
  if slug_style == "name_random" then
    local prefix = slugify(name, name_max_length)
    if prefix ~= "" then return prefix .. "-" .. suffix end
  end
  return suffix
end

return M
