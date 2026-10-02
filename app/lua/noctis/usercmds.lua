-- :Noctis <komut-id> — registry'deki her komut Ex komutu olarak da çağrılabilir.
local M = {}

function M.setup()
  local R = require("noctis.registry")
  vim.api.nvim_create_user_command("Noctis", function(opts)
    local id = opts.fargs[1]
    if not id then
      require("noctis.palette").open()
      return
    end
    R.run(id)
  end, {
    nargs = "?",
    desc = "NOCTIS komutu çalıştır (argümansız: komut paleti)",
    complete = function(arg)
      local out = {}
      for _, c in ipairs(R.list) do
        if c.id:find(arg, 1, true) == 1 then
          out[#out + 1] = c.id
        end
      end
      return out
    end,
  })

  vim.api.nvim_create_user_command("NoctisConflict", function()
    require("noctis.sync").resolve(0)
  end, { desc = "Disk/buffer çatışmasını çöz" })

  vim.api.nvim_create_user_command("NoctisKeys", function()
    local lines = vim.split(R.markdown(), "\n")
    local problems = R.conflicts()
    if #problems > 0 then
      table.insert(lines, 1, "")
      for i = #problems, 1, -1 do
        table.insert(lines, 1, "! " .. problems[i])
      end
      table.insert(lines, 1, "# Kısayol çakışmaları")
    end
    require("noctis.ui.float").text(lines, { title = "Kısayollar", ft = "markdown" })
  end, { desc = "Kısayol listesi ve çakışma raporu" })

  vim.api.nvim_create_user_command("NoctisLang", function(opts)
    require("noctis.lang").command(opts.fargs)
  end, {
    nargs = "*",
    desc = "Dil paketleri: durum / install <dil>",
    complete = function()
      return vim.list_extend({ "install", "status" }, require("noctis.lang").names())
    end,
  })
end

return M
