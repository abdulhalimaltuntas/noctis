-- Project sessions: open files and the window layout (splits) are stored
-- locally. Restoring happens only on an explicit user action; it writes nothing
-- to disk and never overwrites unsaved buffers. Running shell/AI processes are
-- not brought back (that isn't possible).
local M = {}

local U = require("noctis.util")
local api = vim.api

local function path_for(root)
  local key = vim.fn.sha256(root):sub(1, 16)
  return U.state_dir("sessions") .. "/" .. key .. ".json"
end

local function is_file_win(win)
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= "" and api.nvim_win_get_config(win).relative == ""
end

local function serialize(node)
  local kind = node[1]
  if kind == "leaf" then
    local win = node[2]
    if not is_file_win(win) then
      return nil
    end
    local buf = api.nvim_win_get_buf(win)
    local cur = api.nvim_win_get_cursor(win)
    return { type = "leaf", file = api.nvim_buf_get_name(buf), line = cur[1], col = cur[2] }
  end
  local children = {}
  for _, child in ipairs(node[2]) do
    local s = serialize(child)
    if s then
      children[#children + 1] = s
    end
  end
  if #children == 0 then
    return nil
  elseif #children == 1 then
    return children[1]
  end
  return { type = kind, children = children }
end

---@param opts? {notify?:boolean}
function M.save(opts)
  local root = require("noctis.project").root()
  local layout = serialize(vim.fn.winlayout())
  local files = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_get_name(b)
    if vim.bo[b].buflisted and vim.bo[b].buftype == "" and name ~= "" and vim.uv.fs_stat(name) then
      files[#files + 1] = name
    end
  end
  if #files == 0 then
    if opts and opts.notify then
      U.info("No open files to save.")
    end
    return
  end
  local cur = api.nvim_buf_get_name(0)
  U.json_write(path_for(root), { root = root, layout = layout, files = files, current = cur, at = os.time() })
  if opts and opts.notify then
    U.info(("Session saved (%d files)."):format(#files))
  end
end

function M.exists(root)
  return vim.uv.fs_stat(path_for(root or require("noctis.project").root())) ~= nil
end

local function open_file(path)
  local existing = vim.fn.bufnr(path)
  if existing > 0 and api.nvim_buf_is_loaded(existing) then
    api.nvim_win_set_buf(0, existing) -- use the open (possibly modified) buffer as is
  else
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

local function build(node)
  if type(node) ~= "table" then
    return
  end
  if node.type == "leaf" then
    if node.file and vim.uv.fs_stat(node.file) then
      open_file(node.file)
      pcall(api.nvim_win_set_cursor, 0, { node.line or 1, node.col or 0 })
    end
    return
  end
  if type(node.children) ~= "table" then
    return
  end
  local wins = { api.nvim_get_current_win() }
  for i = 2, #node.children do
    vim.cmd(node.type == "row" and "rightbelow vsplit" or "rightbelow split")
    wins[i] = api.nvim_get_current_win()
  end
  for i, child in ipairs(node.children) do
    api.nvim_set_current_win(wins[i])
    build(child)
  end
end

function M.restore()
  local root = require("noctis.project").root()
  local data = U.json_read(path_for(root))
  if not data or not data.files then
    U.info("No saved session for this project: " .. vim.fn.fnamemodify(root, ":~"))
    return
  end
  -- Simplify the current window layout without touching unsaved buffers.
  pcall(function()
    require("noctis.ui.dashboard").close()
  end)
  vim.cmd("silent! only")
  local missing = 0
  for _, f in ipairs(data.files) do
    if vim.uv.fs_stat(f) then
      if vim.fn.bufnr(f) < 0 then
        vim.fn.bufadd(f)
        vim.bo[vim.fn.bufnr(f)].buflisted = true
      end
    else
      missing = missing + 1
    end
  end
  if data.layout then
    build(data.layout)
  elseif data.current and vim.uv.fs_stat(data.current) then
    open_file(data.current)
  end
  U.info(("Session restored (%d files%s)."):format(#data.files - missing, missing > 0 and (", " .. missing .. " no longer exist") or ""))
end

function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("noctis_session", { clear = true }),
    callback = function()
      if require("noctis.config").options.session.autosave then
        pcall(M.save)
      end
    end,
  })
end

return M
