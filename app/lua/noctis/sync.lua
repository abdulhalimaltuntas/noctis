-- Buffer ↔ disk synchronization and conflict handling.
--
-- Rules:
--   * Clean buffer: when the disk changes it's reloaded safely; the view is kept,
--     changed lines are briefly highlighted, and the reload can be undone with `u`
--     ('undoreload').
--   * Buffer with unsaved changes: NO automatic reload/save. The buffer is marked
--     as conflicted; on save the current disk version is checked again.
--   * Conflict: compare/merge is offered using the local buffer, the current disk
--     and the content the buffer was last in sync with (the base). Without a base,
--     a manual diff and saving a separate copy are offered.
--   * Deleted/moved file: the buffer content is never lost (it's marked modified).
local M = {}

local U = require("noctis.util")
local api = vim.api

local ns = api.nvim_create_namespace("noctis.sync")

---@type table<integer, string> buffer -> last synced content (known to equal the disk)
M.base = {}
---@type table<integer, {mtime:integer, nsec:integer, size:integer, ino:integer}?> last synced disk state
M.stat = {}
M.MAX_BASE = 4 * 1024 * 1024

local function is_file_buf(buf)
  return api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= ""
end

--- Convert buffer content to text as it would be written to disk.
function M.buf_text(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local nl = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
  local text = table.concat(lines, nl)
  if vim.bo[buf].endofline or vim.bo[buf].fixendofline then
    text = text .. nl
  end
  return text
end

--- Record the base (last synced content) for this buffer.
function M.remember(buf)
  if not is_file_buf(buf) then
    M.base[buf], M.stat[buf] = nil, nil
    return
  end
  local st = vim.uv.fs_stat(api.nvim_buf_get_name(buf))
  M.stat[buf] = st and { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino } or nil
  if vim.b[buf].noctis_bigfile then
    M.base[buf] = nil
    return
  end
  local text = M.buf_text(buf)
  if #text <= M.MAX_BASE then
    M.base[buf] = text
  else
    M.base[buf] = nil
  end
end

local function views_for(buf)
  local views = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
    end
  end
  return views
end

local function restore_views(buf, views)
  local count = api.nvim_buf_line_count(buf)
  for win, view in pairs(views) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      view.lnum = math.min(view.lnum, count)
      view.topline = math.min(view.topline, count)
      pcall(api.nvim_win_call, win, function()
        vim.fn.winrestview(view)
      end)
    end
  end
end

--- Briefly highlight changed lines (restrained: one color, a few seconds).
function M.flash(buf, old_lines)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  local new_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  if #old_lines + #new_lines > 200000 then
    return
  end
  local a = table.concat(old_lines, "\n") .. "\n"
  local b = table.concat(new_lines, "\n") .. "\n"
  local ok, hunks = pcall(vim.text.diff, a, b, { result_type = "indices", algorithm = "histogram" })
  if not ok or type(hunks) ~= "table" then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hunks) do
    local start_b, count_b = h[3], h[4]
    for l = start_b, start_b + count_b - 1 do
      if l >= 1 and l <= #new_lines then
        pcall(api.nvim_buf_set_extmark, buf, ns, l - 1, 0, { line_hl_group = "NoctisFlash", priority = 5 })
      end
    end
  end
  vim.defer_fn(function()
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end, 4000)
end

local pending = {} ---@type table<integer, {lines:string[], views:table}>

---@param buf integer
function M.mark_conflict(buf, reason)
  vim.b[buf].noctis_conflict = { reason = reason, at = os.time() }
  api.nvim_exec_autocmds("User", { pattern = "NoctisConflict", modeline = false, data = { buf = buf, reason = reason } })
  vim.cmd("redrawstatus")
end

function M.clear_conflict(buf)
  if api.nvim_buf_is_valid(buf) and vim.b[buf].noctis_conflict then
    vim.b[buf].noctis_conflict = nil
    vim.cmd("redrawstatus")
  end
end

function M.has_conflict(buf)
  return api.nvim_buf_is_valid(buf) and vim.b[buf].noctis_conflict ~= nil
end

--- FileChangedShell handler (the buffer can't be changed here; only a decision is made).
local function on_changed_shell(ev)
  local buf = ev.buf
  local reason = vim.v.fcs_reason
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":~:.")
  if reason == "deleted" then
    vim.v.fcs_choice = ""
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        -- The content now only lives in this buffer: mark it modified so quitting asks.
        vim.bo[buf].modified = true
        M.mark_conflict(buf, "deleted")
        U.warn(("`%s` was deleted or moved on disk. The content is kept in the buffer.\nSave: Space f s · Options: :NoctisConflict"):format(name))
      end
    end)
  elseif reason == "conflict" or (reason == "changed" and vim.bo[buf].modified) then
    vim.v.fcs_choice = ""
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        M.mark_conflict(buf, "changed")
        U.warn(
          ("`%s` changed on disk, but you have unsaved edits in the buffer.\nNeither was overwritten. Compare/merge: :NoctisConflict"):format(name)
        )
      end
    end)
  elseif reason == "changed" then
    pending[buf] = { lines = api.nvim_buf_get_lines(buf, 0, -1, false), views = views_for(buf) }
    vim.v.fcs_choice = "reload"
  else -- "mode", "time": the content didn't change
    vim.v.fcs_choice = ""
  end
end

local function on_changed_shell_post(ev)
  local buf = ev.buf
  local p = pending[buf]
  pending[buf] = nil
  M.clear_conflict(buf)
  M.remember(buf)
  if p then
    restore_views(buf, p.views)
    M.flash(buf, p.lines)
    api.nvim_exec_autocmds("User", { pattern = "NoctisBufReloaded", modeline = false, data = { buf = buf } })
  end
end

--- Trigger a disk check for specific buffer(s).
function M.check(buf)
  if buf then
    if is_file_buf(buf) then
      pcall(vim.cmd, "checktime " .. buf)
    end
  else
    pcall(vim.cmd, "checktime")
  end
end

--- Has the disk changed since the buffer's last sync? (stat + content)
---@return boolean changed, string? reason  "changed" | "deleted"
function M.disk_changed(buf)
  local path = api.nvim_buf_get_name(buf)
  local st = vim.uv.fs_stat(path)
  local old = M.stat[buf]
  if not st then
    return old ~= nil, "deleted"
  end
  if not old then
    return false
  end
  if st.mtime.sec == old.mtime and st.mtime.nsec == old.nsec and st.size == old.size and st.ino == old.ino then
    return false
  end
  local base = M.base[buf]
  if base then
    local text = U.read_file(path)
    if text == base then
      -- only the timestamp/inode changed (e.g. an atomic save with the same content)
      M.stat[buf] = { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino }
      return false
    end
  end
  return true, "changed"
end

--- The user saw/merged the current disk version: it becomes the new reference.
--- The next save writes without Neovim's built-in "changed since reading"
--- prompt, as long as the disk hasn't changed again since then.
function M.acknowledge(buf)
  local st = vim.uv.fs_stat(api.nvim_buf_get_name(buf))
  M.stat[buf] = st and { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino } or nil
  vim.b[buf].noctis_ack = true
end

--- Content on disk (nil if unreadable)
function M.disk_text(buf)
  return U.read_file(api.nvim_buf_get_name(buf))
end

local function to_lines(text, ff)
  if ff == "dos" then
    text = text:gsub("\r\n", "\n")
  end
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

--- Open the disk version as a read-only scratch buffer and diff it against the local buffer.
function M.diff_with_disk(buf)
  local text = M.disk_text(buf)
  if not text then
    U.warn("The file doesn't exist on disk; there's no version to compare with.")
    return
  end
  local name = api.nvim_buf_get_name(buf)
  vim.cmd("tab split")
  api.nvim_win_set_buf(0, buf)
  vim.cmd("diffthis")
  vim.cmd("leftabove vnew")
  local scratch = api.nvim_get_current_buf()
  vim.bo[scratch].buflisted = false -- keep the temporary buffer out of the tab bar
  api.nvim_buf_set_lines(scratch, 0, -1, false, to_lines(text, vim.bo[buf].fileformat))
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  pcall(api.nvim_buf_set_name, scratch, "disk://" .. vim.fn.fnamemodify(name, ":~:.") .. " (on-disk version)")
  vim.cmd("diffthis")
  vim.wo.winbar = "%#NoctisWarning# DISK %#NoctisMuted# current disk content (read-only)"
  vim.cmd("wincmd l")
  vim.wo.winbar = "%#NoctisAccent# LOCAL %#NoctisMuted# your edits in the buffer · move hunks with `do`/`dp` · save: Space f s"
  U.info("Left: disk, right: local buffer. Move between differences with `]c`/`[c`; close the tab: :tabclose")
end

--- Save the local buffer content to a separate copy (outside the project, in state).
function M.save_copy(buf)
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  local dir = U.state_dir("recovered")
  local path = ("%s/%s.%s.local"):format(dir, name, os.date("%Y%m%d-%H%M%S"))
  local ok, err = U.write_file(path, M.buf_text(buf), 384)
  if ok then
    U.info("Saved a copy of the local version:\n" .. path)
    return path
  end
  U.error("Could not save the copy: " .. tostring(err))
end

--- 3-way merge: base (last sync), local (buffer), disk.
--- The result is written to the buffer (undoable); conflicting sections are
--- left with markers. Nothing is written to disk.
function M.merge(buf)
  local base = M.base[buf]
  local disk = M.disk_text(buf)
  if not base or not disk then
    U.warn("No reliable common base; opening a comparison instead of a merge.")
    return M.diff_with_disk(buf)
  end
  if not U.has("git") then
    U.warn("Merging needs `git merge-file`; opening a comparison.")
    return M.diff_with_disk(buf)
  end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p", "0o700")
  local fl, fb, fd = tmp .. "/local", tmp .. "/base", tmp .. "/disk"
  U.write_file(fl, M.buf_text(buf))
  U.write_file(fb, base)
  U.write_file(fd, disk)
  local res = vim
    .system({ "git", "merge-file", "-p", "-L", "local (buffer)", "-L", "base (last sync)", "-L", "disk (current)", fl, fb, fd }, { text = true })
    :wait(10000)
  vim.fn.delete(tmp, "rf")
  if res.code < 0 or res.code > 127 then
    U.error("Merge failed: " .. (res.stderr or ""))
    return
  end
  local merged = to_lines(res.stdout or "", "unix")
  api.nvim_buf_set_lines(buf, 0, -1, false, merged)
  -- The merged content is now based on the current disk version.
  M.base[buf] = disk
  M.acknowledge(buf)
  if res.code == 0 then
    M.clear_conflict(buf)
    U.info("Merge completed cleanly (buffer updated, not saved yet). Undo: u")
  else
    vim.b[buf].noctis_conflict = { reason = "markers", at = os.time() }
    U.warn(("%d conflicting sections: edit the <<<<<<< / ||||||| / ======= / >>>>>>> markers and save."):format(res.code))
    vim.fn.search("^<<<<<<< ", "w")
  end
  -- Update Neovim's recorded file time so saving doesn't warn again.
  pcall(vim.cmd, "checktime " .. buf)
end

--- Load the disk version into the buffer (a copy of the local edits is kept first).
function M.take_disk(buf)
  if vim.bo[buf].modified then
    M.save_copy(buf)
  end
  api.nvim_buf_call(buf, function()
    vim.cmd("edit!")
  end)
  M.clear_conflict(buf)
  M.remember(buf)
end

--- Conflict resolution menu
function M.resolve(buf, opts)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  opts = opts or {}
  local c = vim.b[buf].noctis_conflict
  local exists = vim.uv.fs_stat(api.nvim_buf_get_name(buf)) ~= nil
  local choices = {}
  if c and c.reason == "deleted" or not exists then
    choices = {
      { "Save again to this path", function()
        api.nvim_buf_call(buf, function()
          vim.cmd("write!")
        end)
        M.clear_conflict(buf)
      end },
      { "Save to a new location…", function()
        require("noctis.files").save_as(buf)
      end },
      { "Keep a copy of the local content", function()
        M.save_copy(buf)
      end },
    }
  else
    choices = {
      { "Compare (disk ↔ local)", function()
        M.diff_with_disk(buf)
      end },
      { "3-way merge (base: last sync)", function()
        M.merge(buf)
      end },
      { "Write the local version (overwrite the disk change)", function()
        M.save_copy_disk(buf)
        api.nvim_buf_call(buf, function()
          vim.cmd("write!")
        end)
        M.clear_conflict(buf)
        M.remember(buf)
      end },
      { "Load the disk version (a local copy is kept first)", function()
        M.take_disk(buf)
      end },
      { "Copy the local content to a separate file", function()
        M.save_copy(buf)
      end },
    }
  end
  local labels = vim.tbl_map(function(x)
    return x[1]
  end, choices)
  vim.ui.select(labels, {
    prompt = opts.on_save and "The disk version changed before saving — what should happen?" or "Disk/buffer conflict",
  }, function(_, idx)
    if idx then
      choices[idx][2]()
    end
  end)
end

--- Keep a copy of the disk version being overwritten — a way back.
function M.save_copy_disk(buf)
  local text = M.disk_text(buf)
  if not text then
    return
  end
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  local path = ("%s/%s.%s.disk"):format(U.state_dir("recovered"), name, os.date("%Y%m%d-%H%M%S"))
  U.write_file(path, text, 384)
  U.log("INFO", "kept the overwritten disk version: " .. path)
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_sync", { clear = true })
  api.nvim_create_autocmd("FileChangedShell", { group = group, callback = on_changed_shell })
  api.nvim_create_autocmd("FileChangedShellPost", { group = group, callback = on_changed_shell_post })
  api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      M.remember(ev.buf)
      if ev.event == "BufWritePost" then
        M.clear_conflict(ev.buf)
      end
    end,
  })
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      M.base[ev.buf], M.stat[ev.buf] = nil, nil
      pending[ev.buf] = nil
    end,
  })
  -- Missed changes: focus regained, entering a buffer, leaving a terminal.
  api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
        M.check(ev.event == "BufEnter" and ev.buf or nil)
      end
    end,
  })
  -- One last check right before writing to disk: if a conflict is marked and
  -- the user didn't resolve it via the NOCTIS save command, the built-in protection applies.
end

return M
