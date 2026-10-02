-- Change review: the list, diff views, the reviewed mark, reverting.
--
-- The two comparisons are labeled separately:
--   * "Review interval": changes detected since the baseline
--   * "Git": the working tree vs HEAD/index (edits made before the baseline included)
--
-- Revert rules:
--   * Without previous content (out of scope) nothing is reverted, and that's said clearly.
--   * If the disk content doesn't match the reviewed version, the operation is refused.
--   * If the file's open buffer has unsaved edits, the operation is refused.
--   * Only the chosen hunk/file changes; the Git index and other files are kept.
--   * The content before the revert is copied to the recovery folder.
local M = {}

local U = require("noctis.util")
local store = require("noctis.ai.store")
local hunks = require("noctis.ai.hunks")
local api = vim.api
local ns = api.nvim_create_namespace("noctis.ai.review")

M.list_buf = nil ---@type integer?
M.mode = "interval" ---@type "interval"|"git"
M.root = nil ---@type string?

local REASON = {
  large = "large file — previous content was not recorded",
  sensitive = "sensitive file — content is never recorded",
  limit = "baseline limit exceeded — no previous content",
  excluded = "excluded — no previous content",
  symlink = "symbolic link — not tracked",
  unreadable = "unreadable — no previous content",
}

local KIND = {
  added = { "A", "NoctisChangeAdded", "added" },
  modified = { "M", "NoctisChangeModified", "modified" },
  deleted = { "D", "NoctisChangeDeleted", "deleted" },
}

local function tracker()
  return M.root and require("noctis.ai.tracker").get(M.root)
end

function M.visible_for(root)
  if not M.list_buf or not api.nvim_buf_is_valid(M.list_buf) or M.root ~= root then
    return false
  end
  return #vim.fn.win_findbuf(M.list_buf) > 0
end

local function base_text(t, rel)
  local e = t.interval.files[rel]
  if not e then
    return "", true
  end
  if not e.hash then
    return nil, false
  end
  return store.get_blob(t.root, e.hash), true
end

local function describe(t, ch)
  if ch.no_baseline then
    return REASON[ch.no_baseline] or ("no previous content (" .. ch.no_baseline .. ")"), "NoctisChangeOutOfScope"
  end
  if ch.binary then
    local e = t.interval.files[ch.rel]
    return ("binary (%s → %s)"):format(e and U.human_size(e.size) or "—", ch.cur_size and U.human_size(ch.cur_size) or "—"), "NoctisMuted"
  end
  if ch.large then
    return "large file — limited preview", "NoctisMuted"
  end
  local parts = {}
  if (ch.adds or 0) > 0 then
    parts[#parts + 1] = "+" .. ch.adds
  end
  if (ch.dels or 0) > 0 then
    parts[#parts + 1] = "−" .. ch.dels
  end
  return table.concat(parts, " "), "NoctisMuted"
end

-- ── List ─────────────────────────────────────────────────────────────────

function M.ensure_list_buf()
  if M.list_buf and api.nvim_buf_is_valid(M.list_buf) then
    return M.list_buf
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "noctis-changes"
  vim.bo[buf].modifiable = false
  vim.b[buf].noctis_panel = true
  vim.b[buf].noctis_label = "Changes"
  pcall(api.nvim_buf_set_name, buf, "noctis://changes")
  M.list_buf = buf
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", function()
    M.open_at_cursor()
  end, "Open the diff")
  map("r", function()
    M.review_at_cursor()
  end, "Toggle reviewed")
  map("u", function()
    M.revert_at_cursor()
  end, "Revert the file to the baseline")
  map("o", function()
    M.edit_at_cursor()
  end, "Open the file in the editor")
  map("g", function()
    M.mode = M.mode == "interval" and "git" or "interval"
    M.render()
  end, "Git / interval view")
  map("R", function()
    local t = tracker()
    if t then
      t:reconcile(function()
        M.render()
      end)
    end
    M.render()
  end, "Refresh")
  map("q", function()
    require("noctis.ai").hide()
  end, "Hide the panel")
  return buf
end

local function cursor_item()
  local buf = M.list_buf
  if not buf or api.nvim_get_current_buf() ~= buf then
    return nil
  end
  local row = api.nvim_win_get_cursor(0)[1]
  return M.meta and M.meta[row]
end

local function git_lines(root)
  local top = require("noctis.git").toplevel(root)
  if not top then
    return { "This folder isn't a Git repository; only the review interval comparison is available." }, {}
  end
  local items = require("noctis.git").status_entries(top) or {}
  local numstat = {}
  local res = vim.system({ "git", "--no-optional-locks", "-C", top, "diff", "--numstat", "HEAD" }, { text = true }):wait(10000)
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local a, d, p = line:match("^(%S+)%s+(%S+)%s+(.+)$")
    if p then
      numstat[p] = { a, d }
    end
  end
  local lines, meta = {}, {}
  lines[#lines + 1] = ("Git changes (vs HEAD) · %s"):format(vim.fn.fnamemodify(top, ":~"))
  lines[#lines + 1] = "Edits made before the baseline are included; this view is independent of the AI interval."
  lines[#lines + 1] = ""
  if #items == 0 then
    lines[#lines + 1] = "  The working tree is clean."
  end
  for _, it in ipairs(items) do
    local ns_ = numstat[it.path]
    local stat = ns_ and ("+" .. ns_[1] .. " −" .. ns_[2]) or (it.x == "?" and "untracked" or "")
    lines[#lines + 1] = ("  %s%s  %-48s %s"):format(it.x, it.y, it.path, stat)
    meta[#lines] = { git = true, path = top .. "/" .. it.path }
  end
  return lines, meta
end

function M.render()
  local buf = M.list_buf
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  local t = tracker()
  local lines, meta, hls = {}, {}, {}
  local function add(text, hl, m)
    lines[#lines + 1] = text
    if hl then
      hls[#hls + 1] = { #lines - 1, hl }
    end
    if m then
      meta[#lines] = m
    end
  end
  if M.mode == "git" then
    local gl, gm = git_lines(M.root or require("noctis.project").root())
    for i, l in ipairs(gl) do
      add(l, i == 1 and "NoctisAccent" or (i == 2 and "NoctisDim" or nil), gm[i])
    end
    add("")
    add("Enter: Git diff · g: back to the review interval · q: hide", "NoctisDim")
  elseif not t then
    -- First open: explain the review model in one screen. Keys come from the
    -- registry, so user overrides show up here too.
    local R = require("noctis.registry")
    local function key(id)
      local c = R.by_id[id]
      local k = c and R.effective_keys(c)
      return k and R.pretty_keys(k) or nil
    end
    add("AI change review", "NoctisAccent")
    add("Every file an AI tool writes is tracked here, shown as a diff and reversible.", "NoctisMuted")
    add("")
    local steps = {
      { "Start an AI tool", key("ai.new"), "The project's on-disk content is recorded first: the baseline." },
      { "Let it work", nil, "Each file it writes appears here: A added · M modified · D deleted." },
      { "Review", "Enter", "Opens the diff against the baseline; r marks a file reviewed." },
      { "Keep or revert", "u · X in the diff", "Revert a whole file, or a single hunk." },
    }
    for i, st in ipairs(steps) do
      local num, title = ("  %d  "):format(i), st[1]
      local text = num .. title .. (st[2] and ("  ·  " .. st[2]) or "")
      add(text)
      local row = #lines - 1
      hls[#hls + 1] = { row, "NoctisAccent", 2, 3 }
      hls[#hls + 1] = { row, "NoctisBold", #num, #num + #title }
      if st[2] then
        hls[#hls + 1] = { row, "NoctisPaletteKey", #text - #st[2], #text }
      end
      add("     " .. st[3], "NoctisMuted")
    end
    add("")
    add("A revert is refused while your own buffer has unsaved edits; the replaced content", "NoctisDim")
    add("is copied to the recovery folder first.", "NoctisDim")
    local cp = key("ai.checkpoint")
    if cp then
      add(("Later, %s starts a fresh interval from the current state."):format(cp), "NoctisDim")
    end
  else
    local iv = t.interval
    local win = vim.fn.bufwinid(buf)
    local width = win ~= -1 and api.nvim_win_get_width(win) or 100
    local head = ("Review interval · baseline %s · "):format(os.date("%Y-%m-%d %H:%M", iv.created_at))
    add(head .. U.shorten_path(vim.fn.fnamemodify(t.root, ":~"), math.max(16, width - vim.fn.strdisplaywidth(head) - 1)), "NoctisAccent")
    add("Changes detected in this interval — which program wrote them is not verified.", "NoctisDim")
    if iv.git and iv.git.head and iv.git.head ~= "" then
      local pre = #(iv.git.entries or {})
      add(("Git: %s @ %s · %s already modified/untracked at the baseline (not counted as new changes)"):format(iv.git.branch or "?", iv.git.head:sub(1, 7), U.plural(pre, "file")), "NoctisDim")
    end
    local running = require("noctis.ai.sessions").running(t.root)
    if #running > 1 then
      add(("⚠ %d AI sessions are running in the same working tree: concurrent write risk. A single editing tool is recommended."):format(#running), "NoctisWarning")
    end
    if t.watcher.overflow then
      add("⚠ Watch limit reached; some folders are tracked by periodic scans (may appear with a delay).", "NoctisWarning")
    end
    add("")
    local list = t:list()
    if #list == 0 then
      add("  No changes yet. They show up here when a program writes a file.", "NoctisDim")
    end
    local namew = 20
    for _, ch in ipairs(list) do
      namew = math.max(namew, math.min(56, vim.fn.strdisplaywidth(ch.rel)))
    end
    for _, ch in ipairs(list) do
      local k = KIND[ch.kind]
      local desc, dhl = describe(t, ch)
      local reviewed = t:is_reviewed(ch.rel)
      local name = U.shorten_path(ch.rel, namew)
      local text = ("  %s  %s%s  %s%s"):format(k[1], name, string.rep(" ", namew - vim.fn.strdisplaywidth(name)), desc, reviewed and "   ✓ reviewed" or "")
      add(text, nil, { rel = ch.rel })
      local row = #lines - 1
      hls[#hls + 1] = { row, k[2], 2, 3 }
      local dstart = 2 + 1 + 2 + #name + (namew - vim.fn.strdisplaywidth(name)) + 2
      hls[#hls + 1] = { row, dhl, dstart, dstart + #desc }
      if reviewed then
        hls[#hls + 1] = { row, "NoctisChangeReviewed", #text - #"✓ reviewed", #text }
      end
    end
    add("")
    local s = iv.stats or {}
    add(
      ("Scope: content of %s recorded · %s out of scope%s · Space a i: details"):format(
        U.plural(s.captured or 0, "file"),
        U.plural(s.skipped or 0, "file"),
        s.limit_hit and (" · limit: " .. s.limit_hit) or ""
      ),
      "NoctisDim"
    )
    add("Enter: diff · r: reviewed · u: revert file · o: open · g: Git view · R: refresh · q: hide", "NoctisDim")
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    if h[3] then
      pcall(api.nvim_buf_set_extmark, buf, ns, h[1], h[3], { end_col = math.min(h[4], #lines[h[1] + 1]), hl_group = h[2] })
    else
      pcall(api.nvim_buf_set_extmark, buf, ns, h[1], 0, { line_hl_group = h[2] })
    end
  end
  M.meta = meta
end

function M.set_root(root)
  M.root = root
end

-- ── Diff views ───────────────────────────────────────────────────────────

--- An unlisted, read-only temporary buffer (never shown in the tab bar)
function M.scratch(lines, ft)
  local b = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "wipe"
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  vim.bo[b].buflisted = false
  if ft and ft ~= "" then
    vim.bo[b].filetype = ft
  end
  return b
end

local function to_lines(text)
  local out = {}
  for _, c in ipairs(hunks.chunks(text or "")) do
    out[#out + 1] = hunks.display(c)
  end
  return out
end

local function guard(t, rel, viewed_hash)
  local abs = t:abs(rel)
  local buf = vim.fn.bufnr(abs)
  if buf > 0 and api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
    return false, "This file's buffer has unsaved edits. Save or discard them first; reverting is never done blindly."
  end
  local cur = U.read_file(abs)
  local cur_hash = cur and store.hash(cur) or "deleted"
  if viewed_hash and cur_hash ~= viewed_hash then
    t:mark(rel)
    return false, "The file changed again after the version you reviewed. Review the diff again; the old content was not written blindly."
  end
  return true, nil, cur
end

local function backup(t, rel, cur)
  if not cur then
    return
  end
  local name = vim.fn.fnamemodify(rel, ":t")
  local path = ("%s/%s.%s.before-revert"):format(U.state_dir("recovered"), name, os.date("%Y%m%d-%H%M%S"))
  U.write_file(path, cur, 384)
  U.log("INFO", "kept the content before the revert: " .. path)
end

local function after_write(t, rel)
  local buf = vim.fn.bufnr(t:abs(rel))
  if buf > 0 and api.nvim_buf_is_loaded(buf) then
    require("noctis.sync").check(buf)
  end
  t:mark(rel)
end

--- Revert a file to its baseline content
function M.revert_file(t, rel, viewed_hash)
  local ch = t.changes[rel]
  if not ch then
    U.info("This file has no interval changes.")
    return false
  end
  if ch.no_baseline then
    U.warn(("Can't revert: %s."):format(REASON[ch.no_baseline] or "no previous content"))
    return false
  end
  local ok, err, cur = guard(t, rel, viewed_hash)
  if not ok then
    U.warn(err)
    return false
  end
  local abs = t:abs(rel)
  if ch.kind == "added" then
    if vim.fn.confirm(("`%s` didn't exist at the baseline. Move it to the NOCTIS trash?"):format(rel), "&Yes\n&No", 2) ~= 1 then
      return false
    end
    local tok, terr = require("noctis.trash").move(abs)
    if not tok then
      U.error("Could not move it: " .. tostring(terr))
      return false
    end
    local buf = vim.fn.bufnr(abs)
    if buf > 0 then
      require("noctis.buffers").delete(buf, { force = true })
    end
    t:mark(rel)
    U.info("Removed the added file (restorable from the trash): " .. rel)
    return true
  end
  local e = t.interval.files[rel]
  local data = store.get_blob(t.root, e.hash)
  if not data or store.hash(data) ~= e.hash then
    U.error("The baseline content is unreadable or corrupt; nothing was reverted.")
    return false
  end
  local msg = ch.kind == "deleted" and ("Recreate `%s` with its baseline content?"):format(rel)
    or ("Revert `%s` to its baseline content? Every interval change in this file is undone."):format(rel)
  if vim.fn.confirm(msg, "&Revert\n&Cancel", 2) ~= 1 then
    return false
  end
  backup(t, rel, cur)
  local wok, werr = U.write_file(abs, data, e.mode or 420)
  if not wok then
    U.error("Could not write: " .. tostring(werr))
    return false
  end
  after_write(t, rel)
  U.info("Reverted to the baseline content: " .. rel)
  return true
end

--- Revert a single hunk only
function M.revert_hunk(t, rel, viewed_hash, h)
  local ch = t.changes[rel]
  if not ch or ch.kind ~= "modified" or ch.no_baseline or ch.binary then
    U.warn("Hunk revert works only on modified text files whose previous content was recorded.")
    return false
  end
  local ok, err, cur = guard(t, rel, viewed_hash)
  if not ok then
    U.warn(err)
    return false
  end
  local base = base_text(t, rel)
  if not base or not cur then
    return false
  end
  local new = hunks.revert_hunk(base, cur, h)
  backup(t, rel, cur)
  local st = vim.uv.fs_stat(t:abs(rel))
  local wok, werr = U.write_file(t:abs(rel), new, st and st.mode % 4096 or 420)
  if not wok then
    U.error("Could not write: " .. tostring(werr))
    return false
  end
  after_write(t, rel)
  U.info(("Hunk reverted (%s, around line %d). The other changes are kept."):format(rel, h[3]))
  return true
end

--- Unified diff (narrow screens or preference)
function M.unified(t, rel, win)
  local base, has = base_text(t, rel)
  local ch = t.changes[rel]
  if not has or not ch or ch.no_baseline then
    U.warn(("`%s`: %s"):format(rel, ch and (REASON[ch.no_baseline] or "no previous content") or "no changes"))
    return
  end
  if ch.binary then
    U.info(("`%s` is a binary file; a text diff can't be shown (%s)."):format(rel, (describe(t, ch))))
    return
  end
  local cur = U.read_file(t:abs(rel)) or ""
  local viewed = ch.kind == "deleted" and "deleted" or store.hash(cur)
  local hk = hunks.diff(base or "", cur)
  if not hk then
    U.warn("The file exceeds the preview limit; try the side-by-side view.")
    return
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "noctis-diff"
  vim.b[buf].noctis_panel = true
  local body, meta = hunks.unified(base or "", cur, hk, 3)
  local k = KIND[ch.kind]
  local header = {
    ("%s  %s  ·  %s  ·  %s%s"):format(k[1], rel, k[3], U.plural(#hk, "hunk"), t:is_reviewed(rel) and "  ·  ✓ reviewed" or ""),
    "]h/[h: hunk · X: revert hunk · U: revert file · m: reviewed · o: open file · q: back to the list",
    "",
  }
  local lines = vim.list_extend(vim.deepcopy(header), body)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local off = #header
  api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = "NoctisDiffFile" })
  api.nvim_buf_set_extmark(buf, ns, 1, 0, { line_hl_group = "NoctisDim" })
  for i, m in pairs(meta) do
    local group = ({ hunk = "NoctisDiffHunk", add = "NoctisDiffAdd", del = "NoctisDiffDel", ctx = "NoctisDiffContext" })[m.kind]
    if group then
      api.nvim_buf_set_extmark(buf, ns, i - 1 + off, 0, { line_hl_group = group })
    end
  end
  api.nvim_win_set_buf(win, buf)
  local function hunk_here()
    local row = api.nvim_win_get_cursor(win)[1] - off
    local m = meta[row]
    return m and m.hunk, m and m.line
  end
  local function back()
    if M.list_buf and api.nvim_win_is_valid(win) then
      api.nvim_win_set_buf(win, M.list_buf)
      M.render()
    end
  end
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("q", back)
  map("]h", function()
    local row = api.nvim_win_get_cursor(win)[1]
    for i = row + 1, #lines do
      if meta[i - off] and meta[i - off].kind == "hunk" then
        return api.nvim_win_set_cursor(win, { i, 0 })
      end
    end
  end)
  map("[h", function()
    local row = api.nvim_win_get_cursor(win)[1]
    for i = row - 1, 1, -1 do
      if meta[i - off] and meta[i - off].kind == "hunk" then
        return api.nvim_win_set_cursor(win, { i, 0 })
      end
    end
  end)
  map("X", function()
    local hi = hunk_here()
    if hi and M.revert_hunk(t, rel, viewed, hk[hi]) then
      M.unified(t, rel, win)
    end
  end)
  map("U", function()
    if M.revert_file(t, rel, viewed) then
      back()
    end
  end)
  map("m", function()
    t:mark_reviewed(rel)
    M.unified(t, rel, win)
  end)
  map("o", function()
    local _, line = hunk_here()
    require("noctis.ui.layout").focus_editor()
    vim.cmd("edit " .. vim.fn.fnameescape(t:abs(rel)))
    if line then
      pcall(api.nvim_win_set_cursor, 0, { math.max(1, line), 0 })
    end
  end)
  -- Go to the first hunk
  for i = 1, #lines do
    if meta[i - off] and meta[i - off].kind == "hunk" then
      pcall(api.nvim_win_set_cursor, win, { i, 0 })
      break
    end
  end
end

--- Side-by-side diff (wide screens): left the baseline (read-only), right the current file.
function M.side_by_side(t, rel)
  local base, has = base_text(t, rel)
  local ch = t.changes[rel]
  if not has or not ch or ch.no_baseline then
    U.warn(("`%s`: %s"):format(rel, ch and (REASON[ch.no_baseline] or "no previous content") or "no changes"))
    return
  end
  if ch.binary then
    U.info(("`%s` is a binary file; a text diff can't be shown (%s)."):format(rel, (describe(t, ch))))
    return
  end
  local abs = t:abs(rel)
  local cur = U.read_file(abs)
  local viewed = cur and store.hash(cur) or "deleted"
  local right_buf
  if cur then
    right_buf = vim.fn.bufadd(abs)
    vim.fn.bufload(right_buf)
    vim.bo[right_buf].buflisted = true
  else
    right_buf = M.scratch({ "(file deleted)" }, "")
  end
  -- New windows inherit the current window's local options; open from the
  -- editor window, not from the panel (Workbench).
  require("noctis.ui.layout").focus_editor()
  -- Open the tab directly with the target buffer so tabnew doesn't leave an empty buffer
  vim.cmd("tab sbuffer " .. right_buf)
  local right = api.nvim_get_current_win()
  vim.cmd("diffthis")
  local sb = M.scratch(to_lines(base), vim.filetype.match({ filename = abs }) or "")
  pcall(api.nvim_buf_set_name, sb, "noctis://baseline/" .. rel)
  vim.cmd("leftabove vertical sbuffer " .. sb)
  local left = api.nvim_get_current_win()
  vim.cmd("diffthis")
  for _, w in ipairs({ left, right }) do
    vim.wo[w].winhighlight = ""
    vim.wo[w].number = true
    vim.wo[w].signcolumn = "yes"
    vim.wo[w].wrap = false
    vim.wo[w].cursorline = true
  end
  vim.cmd("wincmd =")
  local bar = require("noctis.ui.bar")
  vim.wo[right].winbar = bar.build({
    { text = " CURRENT DISK ", hl = "NoctisAccent" },
    { text = " " .. rel, hl = "NoctisMuted" },
    { text = "  ·  Space a h: revert hunk · Space a m: reviewed", hl = "NoctisDim", drop = 2 },
  }, api.nvim_win_get_width(right))
  vim.wo[left].winbar = bar.build({
    { text = " BASELINE ", hl = "NoctisWarning" },
    { text = " " .. os.date("%H:%M", t.interval.created_at) .. " · read-only", hl = "NoctisMuted", drop = 3 },
    { text = " · X: revert hunk · U: file · m: reviewed · q: close", hl = "NoctisDim", drop = 2 },
  }, api.nvim_win_get_width(left))
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = sb, nowait = true, silent = true })
  end
  map("q", function()
    vim.cmd("tabclose")
  end)
  map("m", function()
    t:mark_reviewed(rel)
  end)
  map("U", function()
    if M.revert_file(t, rel, viewed) then
      vim.cmd("tabclose")
    end
  end)
  map("X", function()
    local hk = hunks.diff(base or "", cur or "")
    if not hk or #hk == 0 then
      return
    end
    -- Map the left (baseline) line to the hunk
    local line = api.nvim_win_get_cursor(left)[1]
    local pick
    for i, h in ipairs(hk) do
      local s, e = h[1], h[2] > 0 and (h[1] + h[2] - 1) or (h[1] + 1)
      if line >= s and line <= e then
        pick = i
      end
    end
    pick = pick or hunks.hunk_at(hk, line)
    if pick and M.revert_hunk(t, rel, viewed, hk[pick]) then
      vim.cmd("tabclose")
      M.side_by_side(t, rel)
    end
  end)
  api.nvim_set_current_win(right)
end

function M.open_diff(t, rel)
  if vim.o.columns >= 140 then
    M.side_by_side(t, rel)
  else
    local win = vim.fn.bufwinid(M.list_buf or -1)
    if win == -1 then
      win = api.nvim_get_current_win()
    end
    M.unified(t, rel, win)
  end
end

function M.open_at_cursor()
  local item = cursor_item()
  if not item then
    return
  end
  if item.git then
    require("noctis.ui.layout").focus_editor()
    vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    require("noctis.git").diff_file()
    return
  end
  local t = tracker()
  if t and item.rel then
    M.open_diff(t, item.rel)
  end
end

function M.review_at_cursor()
  local item, t = cursor_item(), tracker()
  if item and item.rel and t then
    t:mark_reviewed(item.rel)
  end
end

function M.revert_at_cursor()
  local item, t = cursor_item(), tracker()
  if item and item.rel and t then
    local ch = t.changes[item.rel]
    M.revert_file(t, item.rel, ch and (ch.cur_hash or (ch.kind == "deleted" and "deleted") or nil))
    M.render()
  end
end

function M.edit_at_cursor()
  local item, t = cursor_item(), tracker()
  local path = item and (item.path or (t and item.rel and t:abs(item.rel)))
  if path and vim.uv.fs_stat(path) then
    require("noctis.ui.layout").focus_editor()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

-- ── Commands for the file in the editor (Space a h / a U / a m) ──────────

local function current_change()
  local abs = api.nvim_buf_get_name(0)
  if abs == "" then
    return nil
  end
  for root, t in pairs(require("noctis.ai.tracker").by_root) do
    local rel = U.relpath(root, abs)
    if rel and t.changes[rel] then
      return t, rel
    end
  end
end

function M.current_revert_hunk()
  local t, rel = current_change()
  if not t then
    U.info("This file has no review interval changes.")
    return
  end
  if vim.bo.modified then
    U.warn("There are unsaved edits; save or discard them first.")
    return
  end
  local cur = U.read_file(t:abs(rel)) or ""
  local base = base_text(t, rel)
  if not base then
    U.warn("No previous content; can't revert.")
    return
  end
  local hk = hunks.diff(base, cur)
  if not hk or #hk == 0 then
    return
  end
  local idx, dist = hunks.hunk_at(hk, api.nvim_win_get_cursor(0)[1])
  if not idx then
    return
  end
  if dist and dist > 0 then
    U.info("The cursor isn't on a change; the nearest hunk was chosen.")
  end
  local h = hk[idx]
  local msg = ("Revert the hunk around line %d (−%d +%d) to its baseline content?"):format(h[3], h[2], h[4])
  if vim.fn.confirm(msg, "&Revert\n&Cancel", 2) == 1 then
    M.revert_hunk(t, rel, store.hash(cur), h)
  end
end

function M.current_revert_file()
  local t, rel = current_change()
  if not t then
    U.info("This file has no review interval changes.")
    return
  end
  local ch = t.changes[rel]
  M.revert_file(t, rel, ch.cur_hash or (ch.kind == "deleted" and "deleted") or nil)
end

function M.current_mark_reviewed()
  local t, rel = current_change()
  if not t then
    U.info("This file has no review interval changes.")
    return
  end
  t:mark_reviewed(rel)
  U.info((t:is_reviewed(rel) and "Reviewed: " or "Reviewed mark removed: ") .. rel)
end

return M
