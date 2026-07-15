local M = {}

local function install(mod)
  for k, v in pairs(mod) do
    M[k] = v
  end
end

install(require("lib.db.schema"))
install(require("lib.db.monitors"))
install(require("lib.db.settings"))
install(require("lib.db.nodes"))
install(require("lib.db.channels"))

return M
