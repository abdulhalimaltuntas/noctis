-- Sistem panosu: kullanılabiliyorsa kullan; değilse açıkça bildir ve
-- editörün kendi kayıtlarıyla (registers) çalışmaya devam et.
local M = {}

M.state = "unknown" ---@type "unknown"|"system"|"internal"|"unavailable"

--- Sağlayıcı algılaması başlangıcı yavaşlatmasın diye ertelenir.
function M.setup()
  local mode = require("noctis.config").options.clipboard
  if mode == "internal" then
    M.state = "internal"
    return
  end
  vim.schedule(function()
    if vim.fn.has("clipboard") == 1 then
      vim.opt.clipboard = "unnamedplus"
      M.state = "system"
    else
      M.state = "unavailable"
      vim.api.nvim_create_autocmd("TextYankPost", {
        once = true,
        callback = function()
          require("noctis.util").info(
            "Sistem panosu kullanılamıyor (xclip, xsel veya wl-clipboard bulunamadı).\n"
              .. "Kopyalanan metin NOCTIS içi kayıtlarda; p ile yapıştırabilirsiniz. Ayrıntı: noctis --doctor"
          )
        end,
      })
    end
  end)
end

function M.provider()
  if vim.fn.has("clipboard") == 0 then
    return nil
  end
  local ok, name = pcall(vim.fn["provider#clipboard#Executable"])
  return ok and name ~= "" and name or "bilinmiyor"
end

return M
