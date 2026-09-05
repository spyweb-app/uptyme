local runtime_config = require("lib.runtime_config")

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
  local config = runtime_config.status_page()
  local suffix = random_suffix(config.random_length or 5)
  if config.slug_style == "name_random" then
    local prefix = slugify(name, config.name_max_length or 20)
    if prefix ~= "" then return prefix .. "-" .. suffix end
  end
  return suffix
end

return M
