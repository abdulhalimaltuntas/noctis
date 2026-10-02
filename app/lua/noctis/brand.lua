-- Ürün kimliği: app/BRAND dosyasından okunur (tek kaynak).
local M = {
  name = "NOCTIS",
  command = "noctis",
  appname = "noctis",
  version = "0.0.0",
  min_nvim = "0.12.0",
}

local home = vim.env.NOCTIS_HOME or vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
M.home = home

local f = io.open(home .. "/BRAND", "r")
if f then
  for line in f:lines() do
    local k, v = line:match("^([A-Z_]+)=(.*)$")
    if k == "NAME" then
      M.name = v
    elseif k == "COMMAND" then
      M.command = v
    elseif k == "APPNAME" then
      M.appname = v
    elseif k == "VERSION" then
      M.version = v
    elseif k == "MIN_NVIM" then
      M.min_nvim = v
    end
  end
  f:close()
end

return M
