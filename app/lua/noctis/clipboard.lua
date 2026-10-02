-- System clipboard: use it when available; otherwise say so clearly and keep
-- working with the editor's own registers.
local M = {}

M.state = "unknown" ---@type "unknown"|"system"|"internal"|"unavailable"

--- Provider detection is deferred so it doesn't slow down startup.
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
            "System clipboard is not available (xclip, xsel or wl-clipboard not found).\n"
              .. "Yanked text stays in NOCTIS registers; paste it with p. Details: noctis --doctor"
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
  return ok and name ~= "" and name or "unknown"
end

return M
