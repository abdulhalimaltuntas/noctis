-- `noctis --setup`: downloads plugins at the commits from the lockfile.
-- Explains what will be downloaded first; reports the result via the exit code.
-- Language servers/parsers are not downloaded (the user picks them with :NoctisLang).
local M = {}

local function out(s)
  io.stdout:write(s .. "\n")
end

function M.run()
  local lazy_ok = package.loaded["lazy"] ~= nil
  if not lazy_ok then
    out("Could not load lazy.nvim (check your network connection and git installation).")
    vim.cmd("cquit 1")
    return
  end
  local Config = require("lazy.core.config")
  local lock = require("noctis.util").json_read(require("noctis.lazy").lockfile) or {}
  out("")
  out("NOCTIS plugin setup")
  out("Target: " .. Config.options.root)
  out("Plugins (versions from the lockfile):")
  local names = vim.tbl_keys(Config.plugins)
  table.sort(names)
  for _, name in ipairs(names) do
    local l = lock[name]
    out(("  • %-22s %s"):format(name, l and (l.commit:sub(1, 7) .. " (" .. (l.branch or "?") .. ")") or "unpinned (latest compatible version)"))
  end
  out("Language servers, formatters and Tree-sitter parsers are not downloaded; pick and install them inside NOCTIS with :NoctisLang.")
  out("")

  -- Bring already-installed plugins to the lockfile commits too
  if next(lock) then
    require("lazy").restore({ wait = true, show = false })
  else
    require("lazy").install({ wait = true, show = false })
  end

  local missing = {}
  for _, name in ipairs(names) do
    local p = Config.plugins[name]
    if not (p and p._.installed) then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    out("Plugins that failed to install: " .. table.concat(missing, ", "))
    out("Check your network connection and run `noctis --setup` again. The editor also opens without these plugins.")
    vim.cmd("cquit 1")
    return
  end
  out(("Done: %d plugins ready. A normal launch no longer needs the network."):format(#names))
  out("Next step: noctis --doctor  ·  noctis")
  vim.cmd("qall!")
end

return M
