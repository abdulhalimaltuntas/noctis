-- Help: modes, the basic flow, getting out of terminals, and grouped keymaps.
-- The keymap section is generated from the registry (same source as the command palette).
local M = {}

local R = require("noctis.registry")

function M.lines()
  local brand = require("noctis.brand")
  local out = {
    "# " .. brand.name .. " — quick help",
    "",
    brand.name .. " is built on Neovim: modal editing is kept.",
    "",
    "## Modes",
    "  NORMAL  navigation and commands. To type:  i",
    "  INSERT  typing text. To finish:  Esc",
    "  VISUAL  selection:  v  (characters)  V  (lines). y copy · d delete · Esc finish",
    "",
    "## Basic flow",
    "  Space f f   find file           i / Esc   type / back to Normal mode",
    "  Space f s   save                Space Space   command palette",
    "  Space b d   close buffer        Space q q     quit safely",
    "  u / Ctrl-r  undo / redo         /text         search in file (n/N next)",
    "",
    "## Getting out of the terminal and AI panel",
    "  In a terminal, Esc and Ctrl-C go to the application (shell / AI tool).",
    "  Ctrl-\\ e        back to the editor window",
    "  Ctrl-\\ Ctrl-n   Normal mode inside the terminal (scroll, copy); i to type again",
    "  Space a a / Space t t   hide/show the panels (the process keeps running)",
    "",
    "## Windows and buffers",
    "  Ctrl-h/j/k/l  move between windows       [b / ]b  previous/next buffer",
    "  The top bar shows open files (buffers). Neovim tabs (tabpages) are a separate",
    "  concept; only when there is more than one, \"tab 2/3\" appears on the right.",
    "",
  }
  local by_group, order = {}, {}
  for _, c in ipairs(R.list) do
    local k = R.effective_keys(c)
    if k and c.palette ~= false then
      if not by_group[c.group] then
        by_group[c.group] = {}
        order[#order + 1] = c.group
      end
      table.insert(by_group[c.group], ("  %-14s %s"):format(R.pretty_keys(k), c.title))
    end
  end
  for _, g in ipairs(order) do
    out[#out + 1] = "## " .. g
    vim.list_extend(out, by_group[g])
    out[#out + 1] = ""
  end
  out[#out + 1] = "Full list and conflict report: :NoctisKeys · Health check: Space h h"
  return out
end

function M.open()
  require("noctis.ui.float").text(M.lines(), { title = "Help", ft = "markdown", width = 84 })
end

function M.keymaps()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker and not require("noctis.util").is_safe_mode() then
    return Snacks.picker.keymaps()
  end
  vim.cmd("map")
end

return M
