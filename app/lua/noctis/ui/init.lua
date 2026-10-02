-- Arayüz bileşenlerinin kurulumu.
local M = {}

function M.setup()
  require("noctis.ui.statusline").setup()
  require("noctis.ui.tabline").setup()
  require("noctis.ui.layout").setup()
  -- Tema değişince tüm çubuklar aynı anda yeniden çizilir
  vim.api.nvim_create_autocmd("User", {
    pattern = "NoctisThemeChanged",
    group = vim.api.nvim_create_augroup("noctis_ui", { clear = true }),
    callback = function()
      vim.cmd("redrawstatus! | redrawtabline")
    end,
  })
end

return M
