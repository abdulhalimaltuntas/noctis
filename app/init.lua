-- NOCTIS entry point. The launcher loads this file with `nvim -u <app>/init.lua`.
-- User configuration is kept separately: stdpath("config")/config.lua

local home = vim.env.NOCTIS_HOME
if not home or home == "" then
  home = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
  vim.env.NOCTIS_HOME = home
end
vim.opt.rtp:prepend(home)

local ok, err = xpcall(function()
  require("noctis").setup()
end, debug.traceback)

if not ok then
  -- Real configuration errors are never swallowed: log, show, suggest safe mode.
  pcall(function()
    require("noctis.util").log("ERROR", "startup error:\n" .. tostring(err))
  end)
  vim.schedule(function()
    vim.api.nvim_echo({
      { "NOCTIS failed to start. ", "ErrorMsg" },
      { "Details: :messages  ·  Log: " .. vim.fn.stdpath("state") .. "/noctis.log\n", "WarningMsg" },
      { "To start without plugins: noctis --safe\n\n", "WarningMsg" },
      { tostring(err), "ErrorMsg" },
    }, true, {})
  end)
end
