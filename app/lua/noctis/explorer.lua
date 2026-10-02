-- File explorer: the snacks explorer (Git status, hidden/ignored files).
-- Deletes are routed to the NOCTIS trash (recoverable).
-- Without plugins, netrw is used.
local M = {}

local U = require("noctis.util")

local function snacks()
  if U.is_safe_mode() then
    return nil
  end
  local ok, S = pcall(require, "snacks")
  return ok and S.explorer and S or nil
end

function M.get()
  local S = snacks()
  if not S then
    return nil
  end
  return S.picker.get({ source = "explorer" })[1]
end

function M.width()
  local w = require("noctis.config").options.ui.explorer_width
  local cols = vim.o.columns
  if cols < 100 then
    w = math.min(w, 26)
  end
  return math.max(16, math.min(w, math.floor(cols * 0.4)))
end

function M.open()
  local S = snacks()
  if S then
    if M.get() then
      return M.get():focus()
    end
    return S.explorer.open({ cwd = require("noctis.project").root(), layout = { layout = { width = M.width() } } })
  end
  if vim.fn.exists(":Lexplore") == 2 then
    vim.cmd("Lexplore " .. vim.fn.fnameescape(require("noctis.project").root()))
    vim.cmd("vertical resize " .. M.width())
  else
    U.warn("The file explorer needs snacks.nvim (noctis --setup).")
  end
end

function M.close()
  local p = M.get()
  if p then
    p:close()
  end
end

function M.toggle()
  if M.get() then
    M.close()
  else
    M.open()
  end
end

--- Explorer delete action: confirmation + NOCTIS trash
function M.delete_action(picker)
  local Tree = require("snacks.explorer.tree")
  local Actions = require("snacks.explorer.actions")
  local paths = vim.tbl_map(require("snacks").picker.util.path, picker:selected({ fallback = true }))
  if #paths == 0 then
    return
  end
  local what = #paths == 1 and vim.fn.fnamemodify(paths[1], ":p:~:.") or (#paths .. " items")
  local msg = ("Delete %s?\nIt's moved to the NOCTIS trash; restore it with Space f T."):format(what)
  if vim.fn.confirm(msg, "&Delete\n&Cancel", 2) ~= 1 then
    return
  end
  for _, path in ipairs(paths) do
    local buf = vim.fn.bufnr(path)
    if buf > 0 and vim.bo[buf].modified then
      U.warn(("`%s` has unsaved changes; skipped."):format(vim.fn.fnamemodify(path, ":t")))
    else
      local ok, err = require("noctis.trash").move(path)
      if ok then
        if buf > 0 then
          require("noctis.buffers").delete(buf, { force = true })
        end
      else
        U.error("Could not delete: " .. tostring(err))
      end
      Tree:refresh(vim.fs.dirname(path))
    end
  end
  picker.list:set_selected()
  Actions.update(picker)
end

return M
