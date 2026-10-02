-- Keymaps. Leader-based mappings come from the registry; this file only has
-- small mode-specific ergonomic mappings. Core Vim motion, search and
-- editing behavior is left unchanged.
local M = {}

local map = vim.keymap.set

function M.setup()
  require("noctis.commands")
  require("noctis.registry").apply_keymaps()

  -- Normal mode: move between windows
  map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
  map("n", "<C-j>", "<C-w>j", { desc = "Window below" })
  map("n", "<C-k>", "<C-w>k", { desc = "Window above" })
  map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
  -- Esc: clear search highlight (Normal mode)
  map("n", "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Clear search highlight" })

  -- An extra easy save (not the only way: Space f s works too). In Insert mode
  -- Ctrl-S stays reserved for Neovim's LSP signature help.
  map({ "n", "x" }, "<C-s>", function()
    require("noctis.registry").run("files.save")
  end, { desc = "Save file" })

  -- Visual: keep the selection when indenting
  map("x", "<", "<gv", { desc = "Decrease indent" })
  map("x", ">", ">gv", { desc = "Increase indent" })

  -- Terminal mode: Esc and Ctrl-C go to the application (shell / AI CLI).
  -- The ways out use Neovim's <C-\> prefix and are separate and visible:
  --   Ctrl-\ Ctrl-n  Normal mode inside the terminal (built-in)
  --   Ctrl-\ e       back to the editor window
  map("t", "<C-\\>e", function()
    require("noctis.ui.layout").focus_editor()
  end, { desc = "Back to editor" })
end

return M
