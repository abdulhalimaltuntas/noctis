-- Start screen. Recent files and projects come only from real local data
-- (v:oldfiles and the NOCTIS project history). Not shown when started with a
-- file/folder argument.
local M = {}

local api = vim.api
local U = require("noctis.util")
local ns = api.nvim_create_namespace("noctis.dashboard")

M.buf = nil ---@type integer?

local function keyhint(id)
  local R = require("noctis.registry")
  local c = R.by_id[id]
  local k = c and R.effective_keys(c)
  return k and R.pretty_keys(k) or ""
end

local function recent_files(limit)
  local out, seen = {}, {}
  local state = vim.fn.stdpath("state")
  local data = vim.fn.stdpath("data")
  for _, f in ipairs(vim.v.oldfiles) do
    if #out >= limit then
      break
    end
    local p = vim.fs.normalize(f)
    if not seen[p] and not p:find(state, 1, true) and not p:find(data, 1, true) and not p:match("/%.git/") then
      seen[p] = true
      local st = vim.uv.fs_stat(p)
      if st and st.type == "file" then
        out[#out + 1] = p
      end
    end
  end
  return out
end

local function actions()
  local list = {
    { key = "n", label = "New file", id = "files.new" },
    { key = "f", label = "Find file", id = "files.find" },
    { key = "g", label = "Search project", id = "files.grep" },
    { key = "o", label = "Open project", id = "project.open" },
  }
  if require("noctis.session").exists() then
    list[#list + 1] = { key = "s", label = "Restore session", id = "session.restore" }
  end
  vim.list_extend(list, {
    { key = "w", label = "AI Workbench", id = "ai.toggle" },
    { key = "t", label = "One-minute tour", id = "help.tutorial" },
    { key = "?", label = "Help and keymaps", id = "help" },
    { key = ",", label = "Settings", id = "config.open" },
    { key = "q", label = "Quit", id = "quit" },
  })
  return list
end

---@class noctis.DashLine
---@field text string
---@field hls? {[1]:integer,[2]:integer,[3]:string}[]  col_start, col_end, group
---@field act? fun()

local function render()
  local buf = M.buf
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  local width = api.nvim_win_get_width(win)
  local height = api.nvim_win_get_height(win)
  local W = math.min(64, width - 4)
  local pad = string.rep(" ", math.max(0, math.floor((width - W) / 2)))
  local lines = {} ---@type noctis.DashLine[]
  local icons = require("noctis.ui.icons")
  local logo = (icons.enabled() and "◆ " or "* ") .. require("noctis.brand").name

  local function center(text, group)
    local w = vim.fn.strdisplaywidth(text)
    local p = string.rep(" ", math.max(0, math.floor((width - w) / 2)))
    lines[#lines + 1] = { text = p .. text, hls = { { #p, #p + #text, group } } }
  end
  local function blank()
    lines[#lines + 1] = { text = "" }
  end
  local function section(title)
    lines[#lines + 1] = { text = pad .. title, hls = { { #pad, #pad + #title, "NoctisDashSection" } } }
  end
  local function item(key, label, right, act, label_group)
    local left = ("  %s  %s"):format(key, label)
    local rw = vim.fn.strdisplaywidth(right or "")
    local gap = math.max(2, W - vim.fn.strdisplaywidth(left) - rw)
    if right and right ~= "" and vim.fn.strdisplaywidth(left) + rw + 2 > W then
      right = U.shorten_path(right, math.max(8, W - vim.fn.strdisplaywidth(left) - 2))
      rw = vim.fn.strdisplaywidth(right)
      gap = math.max(2, W - vim.fn.strdisplaywidth(left) - rw)
    end
    local text = pad .. left .. string.rep(" ", gap) .. (right or "")
    local kstart = #pad + 2
    local lstart = kstart + #key + 2
    local hls = {
      { kstart, kstart + #key, "NoctisDashKey" },
      { lstart, lstart + #label, label_group or "NoctisDashDesc" },
    }
    if right and right ~= "" then
      hls[#hls + 1] = { #text - #right, #text, "NoctisDashPath" }
    end
    lines[#lines + 1] = { text = text, hls = hls, act = act, key = key }
  end

  -- Title (small text logo)
  local acts = actions()
  local tall = height >= 30
  local top = tall and math.max(1, math.floor(height * 0.12)) or 1
  for _ = 1, top do
    blank()
  end
  center(logo, "NoctisDashTitle")
  center("Neovim-based terminal coding environment · v" .. require("noctis.brand").version, "NoctisDashSubtitle")
  local proj = require("noctis.project")
  local root = vim.fn.fnamemodify(proj.root(), ":~")
  local ptxt = ("project: %s%s"):format(root, proj.kind() == "git" and "  (git)" or "")
  center(U.shorten_path(ptxt, math.max(20, width - 6)), "NoctisDashPath")
  blank()

  section("Start")
  for _, a in ipairs(acts) do
    item(a.key, a.label, keyhint(a.id), function()
      require("noctis.registry").run(a.id)
    end)
  end

  -- Shorten the lists to fit the remaining height
  local remaining = height - #lines - 4
  local nfiles = math.max(0, math.min(9, math.floor(remaining * 0.6) - 2))
  local nprojects = math.max(0, math.min(5, remaining - nfiles - 5))

  if nfiles > 0 then
    blank()
    section("Recent files")
    local files = recent_files(nfiles)
    if #files == 0 then
      local t = "No recent files yet — press f to find a file or o to open a project."
      lines[#lines + 1] = { text = pad .. "  " .. t, hls = { { #pad, #pad + #t + 2, "NoctisDashEmpty" } } }
    end
    for i, f in ipairs(files) do
      local tail = vim.fn.fnamemodify(f, ":t")
      local dir = vim.fn.fnamemodify(f, ":~:h")
      item(tostring(i), tail, dir, function()
        vim.cmd("edit " .. vim.fn.fnameescape(f))
      end)
    end
  end
  if nprojects > 0 then
    local projects = proj.recent()
    if #projects > 0 then
      blank()
      section("Recent projects")
      local keys = { "a", "b", "c", "d", "e" }
      for i = 1, math.min(nprojects, #projects) do
        local p = projects[i].path
        item(keys[i], vim.fn.fnamemodify(p, ":t"), vim.fn.fnamemodify(p, ":~"), function()
          proj.open(p)
        end)
      end
    end
  end
  blank()
  center("Space Space: command palette  ·  j/k: move  ·  Enter: select", "NoctisDim")

  -- Write
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(l)
      return l.text
    end, lines)
  )
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  M.items = {}
  for i, l in ipairs(lines) do
    for _, h in ipairs(l.hls or {}) do
      pcall(api.nvim_buf_set_extmark, buf, ns, i - 1, h[1], { end_col = math.min(h[2], #l.text), hl_group = h[3] })
    end
    if l.act then
      M.items[#M.items + 1] = { row = i, act = l.act, key = l.key, col = #pad + 2 }
    end
  end
  -- Keymaps
  for _, it in ipairs(M.items) do
    vim.keymap.set("n", it.key, it.act, { buffer = buf, nowait = true, silent = true })
  end
  if M.items[1] and api.nvim_win_is_valid(win) then
    local cur = api.nvim_win_get_cursor(win)[1]
    local found = false
    for _, it in ipairs(M.items) do
      if it.row == cur then
        found = true
      end
    end
    if not found then
      api.nvim_win_set_cursor(win, { M.items[1].row, M.items[1].col })
    end
  end
end

local function move(dir)
  local win = api.nvim_get_current_win()
  local row = api.nvim_win_get_cursor(win)[1]
  local target
  if dir > 0 then
    for _, it in ipairs(M.items) do
      if it.row > row then
        target = it
        break
      end
    end
  else
    for i = #M.items, 1, -1 do
      if M.items[i].row < row then
        target = M.items[i]
        break
      end
    end
  end
  if target then
    api.nvim_win_set_cursor(win, { target.row, target.col })
  end
end

local sel_ns = api.nvim_create_namespace("noctis.dashboard.sel")

--- Highlight the selected item only over the item area (not the whole line)
local function highlight_current()
  local buf = M.buf
  if not buf or not api.nvim_buf_is_valid(buf) or api.nvim_get_current_buf() ~= buf then
    return
  end
  api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)
  local row = api.nvim_win_get_cursor(0)[1]
  for _, it in ipairs(M.items or {}) do
    if it.row == row then
      local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
      api.nvim_buf_set_extmark(buf, sel_ns, row - 1, math.max(0, it.col - 1), {
        end_col = #line,
        hl_group = "NoctisDashSel",
        priority = 50,
      })
    end
  end
end

local function activate()
  local row = api.nvim_win_get_cursor(0)[1]
  for _, it in ipairs(M.items or {}) do
    if it.row == row then
      return it.act()
    end
  end
end

---@param opts? {force?:boolean}
function M.open(opts)
  opts = opts or {}
  local buf = api.nvim_create_buf(false, true)
  M.buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "noctis-dashboard"
  vim.b[buf].noctis_panel = true
  api.nvim_set_current_buf(buf)
  local win = api.nvim_get_current_win()
  for opt, val in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    cursorline = false,
    list = false,
    wrap = false,
    colorcolumn = "",
    foldcolumn = "0",
    statuscolumn = "",
  }) do
    -- :setlocal semantics: the next buffer shown in this window gets the
    -- global values back (line numbers, sign column, ...) instead of the dashboard's.
    api.nvim_set_option_value(opt, val, { scope = "local", win = win })
  end
  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("j", function()
    move(1)
  end)
  map("k", function()
    move(-1)
  end)
  map("<Down>", function()
    move(1)
  end)
  map("<Up>", function()
    move(-1)
  end)
  map("<CR>", activate)
  render()
  highlight_current()
  api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = highlight_current })
  if opts.force then
    -- When opened by command, q closes the dashboard instead of quitting
    map("q", function()
      M.close()
    end)
  end
  api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    buffer = buf,
    callback = function()
      vim.schedule(render)
    end,
  })
  api.nvim_create_autocmd("User", {
    pattern = "NoctisThemeChanged",
    callback = function()
      if not api.nvim_buf_is_valid(buf) then
        return true
      end
      render()
    end,
  })
end

function M.close()
  if M.buf and api.nvim_buf_is_valid(M.buf) then
    local alt = vim.fn.bufnr("#")
    for _, win in ipairs(vim.fn.win_findbuf(M.buf)) do
      if alt > 0 and api.nvim_buf_is_valid(alt) and alt ~= M.buf then
        api.nvim_win_set_buf(win, alt)
      else
        api.nvim_win_call(win, function()
          vim.cmd("enew")
        end)
      end
    end
  end
end

function M.should_show()
  if vim.fn.argc(-1) > 0 or vim.g.noctis_stdin then
    return false
  end
  local buf = api.nvim_get_current_buf()
  if api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].modified then
    return false
  end
  local lines = api.nvim_buf_get_lines(buf, 0, 2, false)
  return #lines <= 1 and (lines[1] or "") == ""
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_dashboard", { clear = true })
  api.nvim_create_autocmd("StdinReadPre", {
    group = group,
    callback = function()
      vim.g.noctis_stdin = true
    end,
  })
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      if M.should_show() then
        local empty = api.nvim_get_current_buf()
        M.open()
        if api.nvim_buf_is_valid(empty) and empty ~= M.buf then
          pcall(api.nvim_buf_delete, empty, {})
        end
      end
      require("noctis.onboarding").maybe_start()
    end,
  })
end

return M
