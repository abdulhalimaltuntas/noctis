-- Interface component setup.
local M = {}

function M.setup()
  require("noctis.ui.statusline").setup()
  require("noctis.ui.tabline").setup()
  require("noctis.ui.layout").setup()
  require("noctis.ui.typing").setup()
  -- When the theme changes, all bars are redrawn together
  vim.api.nvim_create_autocmd("User", {
    pattern = "NoctisThemeChanged",
    group = vim.api.nvim_create_augroup("noctis_ui", { clear = true }),
    callback = function()
      vim.cmd("redrawstatus! | redrawtabline")
    end,
  })
end

return M
