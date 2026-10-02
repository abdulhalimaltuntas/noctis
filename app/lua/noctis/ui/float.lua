-- Shared popup window: fits the screen, closes with Esc/q, follows the theme.
local M = {}

local api = vim.api

---@param lines string[]
---@param opts? {title?:string, ft?:string, width?:integer, height?:integer, footer?:string, enter?:boolean, on_close?:fun(), modifiable?:boolean}
---@return integer buf, integer win
function M.text(lines, opts)
  opts = opts or {}
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = opts.modifiable == true
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = opts.ft or "noctis-info"
  local maxw = 0
  for _, l in ipairs(lines) do
    maxw = math.max(maxw, vim.fn.strdisplaywidth(l))
  end
  local cols, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight - 2
  local width = math.min(opts.width or math.max(maxw + 4, 40), cols - 4)
  local height = math.min(opts.height or #lines, rows - 4)
  width, height = math.max(width, 10), math.max(height, 1)
  local win = api.nvim_open_win(buf, opts.enter ~= false, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((rows - height) / 2) - 1),
    col = math.floor((cols - width) / 2),
    style = "minimal",
    border = require("noctis.ui.icons").border(),
    title = opts.title and (" " .. opts.title .. " ") or nil,
    title_pos = "center",
    footer = opts.footer or " q / Esc: close ",
    footer_pos = "right",
    zindex = 60,
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "Normal:NormalFloat,CursorLine:CursorLine"
  local function close()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    if opts.on_close then
      opts.on_close()
    end
  end
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, close, { buffer = buf, nowait = true, silent = true })
  end
  api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close)
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    buffer = buf,
    callback = function()
      if not api.nvim_win_is_valid(win) then
        return true
      end
      local c, r = vim.o.columns, vim.o.lines - vim.o.cmdheight - 2
      local w, h = math.min(width, c - 4), math.min(height, r - 4)
      api.nvim_win_set_config(win, {
        relative = "editor",
        width = math.max(w, 10),
        height = math.max(h, 1),
        row = math.max(0, math.floor((r - h) / 2) - 1),
        col = math.max(0, math.floor((c - w) / 2)),
      })
    end,
  })
  return buf, win
end

return M
