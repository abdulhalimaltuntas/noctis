-- NOCTIS core orchestration.
local M = {}

M.started_at = vim.uv.hrtime()

local function step(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    -- A failure in one subsystem must not make the whole editor unusable,
    -- but it is never swallowed silently either: log + visible error.
    local U = require("noctis.util")
    U.log("ERROR", ("%s setup failed:\n%s"):format(name, err))
    U.error(("%s failed to start: %s\nLog: %s"):format(name, tostring(err):match("^[^\n]*"), vim.fn.stdpath("state") .. "/noctis.log"))
  end
  return ok
end

function M.setup()
  local brand = require("noctis.brand")
  if vim.fn.has("nvim-" .. brand.min_nvim) == 0 then
    error(("%s requires Neovim >= %s (found: %s)"):format(brand.name, brand.min_nvim, tostring(vim.version())))
  end
  require("noctis.util").title = brand.name

  local cfg = require("noctis.config")
  cfg.load()

  require("noctis.options").setup()
  step("theme", function()
    require("noctis.theme").setup()
    require("noctis.theme").apply()
  end)
  step("autocommands", function()
    require("noctis.autocmds").setup()
  end)
  step("keymaps", function()
    require("noctis.keymaps").setup()
  end)
  step("user commands", function()
    require("noctis.usercmds").setup()
  end)
  step("interface", function()
    require("noctis.ui").setup()
  end)
  step("project", function()
    require("noctis.project").setup()
  end)

  if require("noctis.util").is_safe_mode() then
    M.plugins = false
  else
    step("plugins", function()
      M.plugins = require("noctis.lazy").setup()
    end)
  end

  step("AI Workbench", function()
    require("noctis.ai").setup()
  end)
  step("session", function()
    require("noctis.session").setup()
  end)
  step("dashboard", function()
    require("noctis.ui.dashboard").setup()
  end)

  cfg.report()
end

return M
