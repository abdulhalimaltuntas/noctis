-- Open the user settings file; create it from the annotated example if missing.
local M = {}

function M.open()
  local cfg = require("noctis.config")
  local path = cfg.path
  if not vim.uv.fs_stat(path) then
    local example = require("noctis.brand").home .. "/examples/config.lua"
    local text = require("noctis.util").read_file(example)
      or "-- NOCTIS user settings. Changes apply after a restart.\nreturn {\n  -- theme = \"glacier\",\n}\n"
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    require("noctis.util").write_file(path, text, 420)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  require("noctis.util").info("Restart NOCTIS after saving your settings. Invalid values are reported with an explanation at startup.")
end

return M
