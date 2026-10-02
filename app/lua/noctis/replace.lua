-- Find and replace in the project. Before anything is applied, the scope and
-- every change are shown in a preview; lines can be excluded one by one.
-- Preview and apply use the same engine (ripgrep --replace); while applying,
-- each line is verified to still match the previewed original text,
-- otherwise that line is skipped. The line ending style (CRLF) is preserved.
local M = {}

local U = require("noctis.util")
local api = vim.api
local ns = api.nvim_create_namespace("noctis.replace")

M.MAX = 5000

local function rg_lines(args, r)
  -- text=false: vim.system's "\r\n" normalization would break CRLF lines
  local res = vim.system(args, { cwd = r, text = false }):wait(60000)
  if res.code ~= 0 and res.code ~= 1 then
    return nil, vim.trim(res.stderr or "ripgrep error")
  end
  local out = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local path, rest = line:match("^(.-)%z(.*)$")
    if path then
      local lnum, text = rest:match("^(%d+):(.*)$")
      if lnum then
        out[#out + 1] = { path = path, lnum = tonumber(lnum), text = text }
      end
    end
  end
  return out
end

---@param q {pattern:string, replacement:string, regex:boolean, glob?:string}
function M.collect(q, r)
  local base = { "rg", "--no-heading", "--with-filename", "--line-number", "--null", "--sort", "path", "--color", "never" }
  if not q.regex then
    base[#base + 1] = "--fixed-strings"
  end
  if q.glob and q.glob ~= "" then
    base[#base + 1] = "--glob"
    base[#base + 1] = q.glob
  end
  local orig_args = vim.list_extend(vim.deepcopy(base), { "--", q.pattern })
  local repl_args = vim.list_extend(vim.deepcopy(base), { "--replace", q.replacement, "--", q.pattern })
  local orig, err = rg_lines(orig_args, r)
  if not orig then
    return nil, err
  end
  local repl, err2 = rg_lines(repl_args, r)
  if not repl then
    return nil, err2
  end
  if #orig ~= #repl then
    return nil, "match counts are inconsistent (files may have changed during the search); try again"
  end
  local changes = {}
  for i, o in ipairs(orig) do
    local n = repl[i]
    if n.path == o.path and n.lnum == o.lnum and n.text ~= o.text then
      changes[#changes + 1] = { path = U.norm(r .. "/" .. o.path:gsub("^%./", "")), rel = o.path:gsub("^%./", ""), lnum = o.lnum, old = o.text, new = n.text, on = true }
    end
  end
  return changes
end

local function apply_file(path, list)
  local applied, skipped = 0, 0
  local buf = vim.fn.bufnr(path)
  if buf > 0 and api.nvim_buf_is_loaded(buf) then
    local was_modified = vim.bo[buf].modified
    local dos = vim.bo[buf].fileformat == "dos"
    for _, c in ipairs(list) do
      local cur = api.nvim_buf_get_lines(buf, c.lnum - 1, c.lnum, false)[1]
      local old = dos and c.old:gsub("\r$", "") or c.old
      local new = dos and c.new:gsub("\r$", "") or c.new
      if cur == old then
        api.nvim_buf_set_lines(buf, c.lnum - 1, c.lnum, false, { new })
        applied = applied + 1
      else
        skipped = skipped + 1
      end
    end
    -- Clean buffers are written to disk (consistent with the other files); a
    -- buffer with unsaved edits is only updated, saving stays with the user.
    if not was_modified and applied > 0 and not require("noctis.sync").disk_changed(buf) then
      api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
    end
    return applied, skipped
  end
  local text = U.read_file(path)
  if not text then
    return 0, #list
  end
  local lines = vim.split(text, "\n", { plain = true })
  for _, c in ipairs(list) do
    if lines[c.lnum] == c.old then
      lines[c.lnum] = c.new
      applied = applied + 1
    else
      skipped = skipped + 1
    end
  end
  if applied > 0 then
    local st = vim.uv.fs_stat(path)
    local ok, err = U.write_file(path, table.concat(lines, "\n"), st and st.mode % 4096 or 420)
    if not ok then
      U.error("Could not write: " .. path .. " — " .. tostring(err))
      return 0, #list
    end
  end
  return applied, skipped
end

function M.apply(changes)
  local by_file, order = {}, {}
  for _, c in ipairs(changes) do
    if c.on then
      if not by_file[c.path] then
        by_file[c.path] = {}
        order[#order + 1] = c.path
      end
      table.insert(by_file[c.path], c)
    end
  end
  local total, skipped = 0, 0
  for _, path in ipairs(order) do
    local a, s = apply_file(path, by_file[path])
    total, skipped = total + a, skipped + s
  end
  if skipped > 0 then
    U.warn(("%d changes applied, %d lines skipped (changed after the preview)."):format(total, skipped))
  else
    U.info(("%d changes applied to %d files. In open buffers you can undo with u."):format(total, #order))
  end
end

local function render(st)
  local buf = st.buf
  local lines, meta = {}, {}
  local on = 0
  for _, c in ipairs(st.changes) do
    if c.on then
      on = on + 1
    end
  end
  lines[1] = ("Replace: %s  →  %s"):format(st.q.pattern, st.q.replacement)
  lines[2] = ("Scope: %s · %s · respects .gitignore, hidden files excluded%s"):format(
    vim.fn.fnamemodify(st.root, ":~"),
    st.q.regex and "regex (ripgrep syntax)" or "plain text",
    st.q.glob and st.q.glob ~= "" and (" · glob: " .. st.q.glob) or ""
  )
  lines[3] = ("%d / %d changes selected   ·   a: apply   x: toggle line   X: toggle file   Enter: go to file   q: cancel"):format(on, #st.changes)
  lines[4] = ""
  local hls = { { 0, "NoctisAccent" }, { 1, "NoctisMuted" }, { 2, "NoctisDim" } }
  local last
  for i, c in ipairs(st.changes) do
    if c.rel ~= last then
      if last then
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = c.rel
      hls[#hls + 1] = { #lines - 1, "NoctisDiffFile" }
      meta[#lines] = { file = c.rel }
      last = c.rel
    end
    local mark = c.on and " " or "×"
    lines[#lines + 1] = ("%s %5d - %s"):format(mark, c.lnum, (c.old:gsub("\r$", "")))
    hls[#hls + 1] = { #lines - 1, c.on and "NoctisDiffDel" or "NoctisDim" }
    meta[#lines] = { idx = i }
    lines[#lines + 1] = ("%s %5s + %s"):format(mark, "", (c.new:gsub("\r$", "")))
    hls[#hls + 1] = { #lines - 1, c.on and "NoctisDiffAdd" or "NoctisDim" }
    meta[#lines] = { idx = i }
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(buf, ns, h[1], 0, { line_hl_group = h[2] })
  end
  st.meta = meta
end

---@param q {pattern:string, replacement:string, regex:boolean, glob?:string}
function M.preview(q)
  local r = require("noctis.project").root()
  local changes, err = M.collect(q, r)
  if not changes then
    U.error("Search failed: " .. tostring(err))
    return
  end
  if #changes == 0 then
    U.info("No matches found.")
    return
  end
  if #changes > M.MAX then
    U.warn(("%d matches; for safety at most %d changes are previewed. Narrow the search (glob)."):format(#changes, M.MAX))
    return
  end
  vim.cmd("tabnew")
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "noctis-replace"
  pcall(api.nvim_buf_set_name, buf, "noctis://replace-preview")
  vim.wo.number = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false
  vim.wo.list = false
  local st = { buf = buf, q = q, changes = changes, root = r }
  render(st)
  local function cur_meta()
    return st.meta[api.nvim_win_get_cursor(0)[1]]
  end
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map("x", function()
    local m = cur_meta()
    if m and m.idx then
      st.changes[m.idx].on = not st.changes[m.idx].on
      local pos = api.nvim_win_get_cursor(0)
      render(st)
      pcall(api.nvim_win_set_cursor, 0, pos)
    end
  end, "Exclude/include line")
  map("X", function()
    local m = cur_meta()
    local file = m and (m.file or (m.idx and st.changes[m.idx].rel))
    if file then
      local any_on = false
      for _, c in ipairs(st.changes) do
        if c.rel == file and c.on then
          any_on = true
        end
      end
      for _, c in ipairs(st.changes) do
        if c.rel == file then
          c.on = not any_on
        end
      end
      local pos = api.nvim_win_get_cursor(0)
      render(st)
      pcall(api.nvim_win_set_cursor, 0, pos)
    end
  end, "Exclude/include file")
  map("<CR>", function()
    local m = cur_meta()
    if m and m.idx then
      local c = st.changes[m.idx]
      vim.cmd("tabprevious")
      vim.cmd("edit " .. vim.fn.fnameescape(c.path))
      pcall(api.nvim_win_set_cursor, 0, { c.lnum, 0 })
    end
  end, "Go to file")
  map("a", function()
    local n, files = 0, {}
    for _, c in ipairs(st.changes) do
      if c.on then
        n = n + 1
        files[c.path] = true
      end
    end
    if n == 0 then
      U.info("No changes selected.")
      return
    end
    local msg = ("Apply %d changes to %d files. Continue?"):format(n, vim.tbl_count(files))
    if vim.fn.confirm(msg, "&Apply\n&Cancel", 2) == 1 then
      M.apply(st.changes)
      vim.cmd("tabclose")
    end
  end, "Uygula")
  map("q", function()
    vim.cmd("tabclose")
  end, "Cancel")
end

function M.open()
  vim.ui.input({ prompt = "Search: ", default = vim.fn.expand("<cword>") }, function(pattern)
    if not pattern or pattern == "" then
      return
    end
    vim.ui.input({ prompt = ("Replace '%s' with: "):format(pattern) }, function(replacement)
      if replacement == nil then
        return
      end
      vim.ui.select({ "Plain text", "Regex (ripgrep syntax, $1 groups)" }, { prompt = "Matching" }, function(_, idx)
        if not idx then
          return
        end
        vim.ui.input({ prompt = "File filter (glob, empty = whole project): " }, function(glob)
          if glob == nil then
            return
          end
          M.preview({ pattern = pattern, replacement = replacement, regex = idx == 2, glob = vim.trim(glob) })
        end)
      end)
    end)
  end)
end

return M
