-- Layout: editor focus, focus mode, quickfix and adapting to the screen size.
--   80×24   : basic editing; side panels close / shrink
--   120×35  : balanced standard layout
--   160×45+ : wide previews, optional extra panels
local M = {}

local api = vim.api
local U = require("noctis.util")

M.MIN_COLS, M.MIN_LINES = 60, 16

--- Class: "tiny" | "small" | "standard" | "wide"
function M.size_class()
  local c, l = vim.o.columns, vim.o.lines
  if c < M.MIN_COLS or l < M.MIN_LINES then
    return "tiny"
  elseif c < 100 or l < 30 then
    return "small"
  elseif c < 160 or l < 45 then
    return "standard"
  end
  return "wide"
end

--- Is this an editable main window? (file or empty buffer, not floating)
function M.is_editor_win(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not vim.b[buf].noctis_panel
end

--- Return from a terminal or panel to the editor window.
function M.focus_editor()
  if vim.fn.mode() == "t" then
    vim.cmd("stopinsert")
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if M.is_editor_win(prev) then
    api.nvim_set_current_win(prev)
    return true
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if M.is_editor_win(win) then
      api.nvim_set_current_win(win)
      return true
    end
  end
  return false
end

function M.toggle_qf()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(win)].buftype == "quickfix" then
      vim.cmd("cclose")
      return
    end
  end
  if #vim.fn.getqflist() == 0 then
    U.info("The quickfix list is empty.")
    return
  end
  vim.cmd("botright copen")
end

--- Focus mode: hide side panels (processes keep running), center the code.
M.focus = false
function M.toggle_focus()
  M.focus = not M.focus
  if M.focus then
    pcall(function()
      require("noctis.explorer").close()
    end)
    pcall(function()
      require("noctis.terminal").hide()
    end)
    pcall(function()
      require("noctis.ai").hide()
    end)
    local ok, Snacks = pcall(require, "snacks")
    if ok and Snacks.zen then
      Snacks.zen({ toggles = { dim = false, git_signs = false, diagnostics = true } })
      M.focus = false -- snacks.zen manages its own on/off state
      return
    end
    vim.cmd("only")
    vim.o.showtabline = 0
    vim.wo.number = false
    vim.wo.signcolumn = "no"
    U.info("Focus mode on (turn off: Space u z)")
  else
    vim.o.showtabline = 2
    vim.wo.number = true
    vim.wo.signcolumn = "yes"
  end
end

local warned_tiny = false
function M.adapt()
  local cls = M.size_class()
  if cls == "tiny" then
    vim.o.showtabline = 0
    if not warned_tiny then
      warned_tiny = true
      U.warn(("Terminal is too small (%d×%d). Basic editing works; panels are hidden. At least 80×24 is recommended."):format(vim.o.columns, vim.o.lines))
    end
  elseif not M.focus then
    vim.o.showtabline = 2
    warned_tiny = false
  end
  if cls == "tiny" or cls == "small" then
    -- On narrow screens the code area comes first: the explorer closes
    if vim.o.columns < 90 then
      pcall(function()
        require("noctis.explorer").close()
      end)
    end
  end
  api.nvim_exec_autocmds("User", { pattern = "NoctisLayout", modeline = false, data = { class = cls } })
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_layout", { clear = true })
  api.nvim_create_autocmd("User", { group = group, pattern = "NoctisResized", callback = M.adapt })
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.schedule(M.adapt)
    end,
  })
end

return M
