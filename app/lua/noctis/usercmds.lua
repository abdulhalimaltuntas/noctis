-- :Noctis <command-id> — every registry command can also be called as an Ex command.
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
    desc = "Run a NOCTIS command (no argument: command palette)",
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
  end, { desc = "Resolve a disk/buffer conflict" })

  vim.api.nvim_create_user_command("NoctisKeys", function()
    local lines = vim.split(R.markdown(), "\n")
    local problems = R.conflicts()
    if #problems > 0 then
      table.insert(lines, 1, "")
      for i = #problems, 1, -1 do
        table.insert(lines, 1, "! " .. problems[i])
      end
      table.insert(lines, 1, "# Keymap conflicts")
    end
    require("noctis.ui.float").text(lines, { title = "Keymaps", ft = "markdown" })
  end, { desc = "Keymap list and conflict report" })

  vim.api.nvim_create_user_command("NoctisLang", function(opts)
    require("noctis.lang").command(opts.fargs)
  end, {
    nargs = "*",
    desc = "Language packs: status / install <language>",
    complete = function()
      return vim.list_extend({ "install", "status" }, require("noctis.lang").names())
    end,
  })
end

return M
