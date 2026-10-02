-- Review interval tracking (one instance per project root).
--
-- Flow: watcher event → the path is marked dirty → debounce → write-settle
-- check (size/mtime equal across two readings) → compare with the baseline content →
-- the change list is updated → open buffers are notified via the sync layer
-- (a clean buffer reloads, a dirty buffer is marked as conflicted).
--
-- For missed events: focus regained and a low-frequency reconcile scan.
-- Which program a change came from is unknown; the label is always
-- "change detected in the review interval".
local U = require("noctis.util")
local store = require("noctis.ai.store")
local scope = require("noctis.ai.scope")
local hunks = require("noctis.ai.hunks")
local uv = vim.uv

local M = {}

---@type table<string, noctis.Tracker>
M.by_root = {}

---@class noctis.Change
---@field rel string
---@field kind "added"|"modified"|"deleted"
---@field cur_hash? string
---@field cur_size? integer
---@field binary? boolean
---@field large? boolean
---@field no_baseline? string  reason when there is no previous content
---@field adds? integer
---@field dels? integer
---@field at integer

---@class noctis.Tracker
---@field root string
---@field interval table
---@field changes table<string, noctis.Change>
---@field known table<string, string>
---@field dirty table<string, boolean>
local T = {}
T.__index = T

M.COMPARE_MAX = 32 * 1024 * 1024

local function sig(st)
  if not st then
    return "none"
  end
  return ("%s:%d:%d:%d:%d"):format(st.type, st.size, st.mtime.sec, st.mtime.nsec, st.ino)
end

local function base_sig(e)
  return ("file:%d:%d:%d:%d"):format(e.size or -1, e.mtime or -1, e.nsec or -1, e.ino or -1)
end

function T.new(root, interval)
  local self = setmetatable({
    root = root,
    interval = interval,
    changes = {},
    known = {},
    dirty = {},
    pending_notify = {},
    last_notify = 0,
    self_writes = {},
    reconciling = false,
    stopped = false,
    started_at = uv.hrtime(),
  }, T)
  local cfg = require("noctis.config").options.ai.watch
  self.debounced = U.debounce(cfg.debounce_ms, function()
    self:process()
  end)
  self.watcher = require("noctis.ai.watcher").new(root, function(rel)
    self:mark(rel)
  end)
  self.timer = uv.new_timer()
  -- The reconcile frequency adapts to the cost of the last scan: reconcile_ms
  -- on small projects, at most once every 60 s on large projects (slow scans).
  self.next_reconcile = 0
  self.timer:start(cfg.reconcile_ms, cfg.reconcile_ms, function()
    vim.schedule(function()
      if uv.now() >= self.next_reconcile then
        self:reconcile()
      end
    end)
  end)
  return self
end

function T:stop()
  self.stopped = true
  if self.watcher then
    self.watcher:stop()
  end
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
end

function T:abs(rel)
  return self.root .. "/" .. rel
end

--- A save the user made from inside NOCTIS (to reduce notification noise)
function T:note_self_write(abs)
  local rel = U.relpath(self.root, abs)
  if rel then
    self.self_writes[rel] = uv.now()
  end
end

---@param rel string  "dir/" form: re-check everything under the directory
function T:mark(rel)
  if self.stopped then
    return
  end
  if rel:sub(-1) == "/" then
    for r in pairs(self.interval.files) do
      if r:sub(1, #rel) == rel then
        self.dirty[r] = true
      end
    end
    for r in pairs(self.changes) do
      if r:sub(1, #rel) == rel then
        self.dirty[r] = true
      end
    end
  else
    self.dirty[rel] = true
  end
  self.debounced()
end

--- Compare a single path's state with the baseline.
function T:compute(rel)
  local cfg = require("noctis.config").options.ai.baseline
  local base = self.interval.files[rel]
  local abs = self:abs(rel)
  local st = uv.fs_lstat(abs)
  local prev = self.changes[rel]
  local function set(ch)
    ch.rel = rel
    ch.at = prev and prev.at or os.time()
    self.changes[rel] = ch
  end
  if st and st.type == "directory" then
    return
  end
  self.known[rel] = sig(st)
  if not st then
    if base then
      set({ kind = "deleted", no_baseline = (not base.hash) and base.reason or nil, binary = base.binary })
    else
      self.changes[rel] = nil
    end
    return
  end
  if st.type == "link" then
    if base and base.reason == "symlink" then
      self.changes[rel] = nil
    else
      set({ kind = base and "modified" or "added", no_baseline = "symlink" })
    end
    return
  end
  if st.type ~= "file" then
    return
  end
  if not base then
    local e = { kind = "added", cur_size = st.size }
    if scope.is_sensitive(rel) then
      e.no_baseline = "sensitive"
    elseif st.size > cfg.max_file_size then
      e.large = true
    else
      local data = U.read_file(abs)
      if data then
        e.cur_hash = store.hash(data)
        e.binary = scope.is_binary(data) or nil
        if not e.binary then
          e.adds, e.dels = #hunks.chunks(data), 0
        end
      end
    end
    set(e)
    return
  end
  if base.hash then
    if st.size > M.COMPARE_MAX then
      set({ kind = "modified", large = true, cur_size = st.size })
      return
    end
    local data = U.read_file(abs)
    if not data then
      return
    end
    local h = store.hash(data)
    if h == base.hash then
      self.changes[rel] = nil
      return
    end
    local e = { kind = "modified", cur_hash = h, cur_size = #data }
    if base.binary or scope.is_binary(data) then
      e.binary = true
    else
      local old = store.get_blob(self.root, base.hash)
      local hk = old and hunks.diff(old, data)
      if hk then
        e.adds, e.dels = hunks.stats(hk)
      else
        e.large = true
      end
    end
    set(e)
    return
  end
  -- A file whose content wasn't recorded at the baseline (large/sensitive/limit): metadata only
  if base_sig(base) == sig(st) or (st.size == base.size and st.mtime.sec == base.mtime and st.mtime.nsec == base.nsec) then
    self.changes[rel] = nil
    return
  end
  set({ kind = "modified", no_baseline = base.reason, cur_size = st.size })
end

local function change_key(ch)
  if not ch then
    return "-"
  end
  return ch.kind .. ":" .. (ch.cur_hash or tostring(ch.cur_size))
end

function T:process()
  if self.stopped or not next(self.dirty) then
    return
  end
  local batch = self.dirty
  self.dirty = {}
  local first = {}
  for rel in pairs(batch) do
    first[rel] = sig(uv.fs_lstat(self:abs(rel)))
  end
  -- Write-settle check: the same signature a moment later?
  vim.defer_fn(function()
    if self.stopped then
      return
    end
    local ready, unstable = {}, false
    for rel in pairs(batch) do
      if sig(uv.fs_lstat(self:abs(rel))) == first[rel] then
        ready[#ready + 1] = rel
      else
        self.dirty[rel] = true
        unstable = true
      end
    end
    local fresh = {}
    for _, rel in ipairs(ready) do
      if not self.interval.files[rel] and not self.changes[rel] and uv.fs_lstat(self:abs(rel)) then
        fresh[#fresh + 1] = rel
      end
    end
    local allowed = #fresh > 0 and scope.not_ignored(self.root, fresh) or {}
    local changed = {}
    for _, rel in ipairs(ready) do
      if self.interval.files[rel] or self.changes[rel] or allowed[rel] then
        local before = change_key(self.changes[rel])
        self:compute(rel)
        if change_key(self.changes[rel]) ~= before then
          changed[#changed + 1] = rel
        end
      end
    end
    if unstable then
      self.debounced()
    end
    if #changed > 0 then
      self:after_change(changed)
    end
  end, 120)
end

function T:after_change(changed)
  local sync = require("noctis.sync")
  local now = uv.now()
  local notify = {}
  for _, rel in ipairs(changed) do
    local buf = vim.fn.bufnr(self:abs(rel))
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      sync.check(buf)
    end
    local sw = self.self_writes[rel]
    if not (sw and now - sw < 2000) then
      notify[#notify + 1] = rel
    end
  end
  for _, rel in ipairs(notify) do
    self.pending_notify[rel] = true
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisAIChanges", modeline = false, data = { root = self.root, changed = changed } })
  self:flush_notify()
end

--- Batch notifications: at most once every few seconds, one short message.
function T:flush_notify()
  if not next(self.pending_notify) then
    return
  end
  local now = uv.now()
  local gap = 4000
  if now - self.last_notify < gap then
    if not self.notify_scheduled then
      self.notify_scheduled = true
      vim.defer_fn(function()
        self.notify_scheduled = false
        self:flush_notify()
      end, gap - (now - self.last_notify) + 50)
    end
    return
  end
  local n = vim.tbl_count(self.pending_notify)
  local present = 0
  for rel in pairs(self.pending_notify) do
    if self.changes[rel] then
      present = present + 1
    end
  end
  self.pending_notify = {}
  self.last_notify = now
  if present == 0 then
    return
  end
  local total = vim.tbl_count(self.changes)
  if require("noctis.ai.review").visible_for(self.root) then
    return -- the change list is already open
  end
  U.info(("Changes detected in %d files (%d in the interval). Review: Space a d"):format(n, total), { id = "noctis_ai_changes" })
end

--- Reconcile: compares the file list and the known signatures (asynchronous).
function T:reconcile(cb)
  if self.stopped or self.reconciling then
    return
  end
  self.reconciling = true
  local args = { "rg", "--files", "--hidden", "--no-require-git", "--no-follow", "--color", "never" }
  if not require("noctis.config").options.ai.baseline.respect_gitignore then
    args[#args + 1] = "--no-ignore"
  end
  for d in pairs(scope.skip_dirs) do
    args[#args + 1] = "--glob"
    args[#args + 1] = "!**/" .. d .. "/**"
  end
  local t0 = uv.now()
  local function finish(listed)
    vim.schedule(function()
      self.reconciling = false
      local took = uv.now() - t0
      local base = require("noctis.config").options.ai.watch.reconcile_ms
      self.next_reconcile = uv.now() + math.min(60000, math.max(base, took * 40))
      if self.stopped then
        return
      end
      local cand = {}
      local st = self.interval.stats or {}
      local overflow = (st.listed or 0) > (st.tracked or 0)
      for rel in pairs(listed) do
        local in_base = self.interval.files[rel] ~= nil
        -- If the watch limit was exceeded, files missing from the record are added only via events
        if in_base or self.changes[rel] or not overflow then
          local known = self.known[rel] or (in_base and base_sig(self.interval.files[rel]))
          if not known or known ~= sig(uv.fs_lstat(self:abs(rel))) then
            cand[rel] = true
          end
        end
      end
      for rel, e in pairs(self.interval.files) do
        if not listed[rel] then
          local known = self.known[rel] or base_sig(e)
          if known ~= sig(uv.fs_lstat(self:abs(rel))) then
            cand[rel] = true
          end
        end
      end
      for rel in pairs(self.changes) do
        if not listed[rel] and not uv.fs_lstat(self:abs(rel)) then
          cand[rel] = true
        end
      end
      local n = 0
      for rel in pairs(cand) do
        if self.interval.files[rel] or self.changes[rel] or listed[rel] then
          self.dirty[rel] = true
          n = n + 1
        end
      end
      if n > 0 then
        self:process()
      end
      if cb then
        cb(n)
      end
    end)
  end
  if not U.has("rg") then
    finish({})
    return
  end
  vim.system(args, { cwd = self.root, text = true }, function(res)
    local listed = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      listed[(line:gsub("^%./", ""))] = true
    end
    finish(listed)
  end)
end

function T:mark_reviewed(rel, value)
  local ch = self.changes[rel]
  if not ch then
    return
  end
  local token = change_key(ch)
  if value == nil then
    value = self.interval.reviewed[rel] ~= token
  end
  self.interval.reviewed[rel] = value and token or nil
  store.save_interval(self.root, self.interval)
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisAIChanges", modeline = false, data = { root = self.root } })
end

--- The mark is invalid if the content changed after the review.
function T:is_reviewed(rel)
  local ch = self.changes[rel]
  return ch ~= nil and self.interval.reviewed[rel] == change_key(ch)
end

---@return noctis.Change[]
function T:list()
  local out = vim.tbl_values(self.changes)
  table.sort(out, function(a, b)
    return a.rel < b.rel
  end)
  return out
end

-- ── Module-level API ─────────────────────────────────────────────────────

function M.get(root)
  return M.by_root[root]
end

--- Load the active interval or take a new baseline.
---@param root string
---@param cb fun(t:noctis.Tracker)
---@param opts? {fresh?:boolean}
function M.ensure(root, cb, opts)
  opts = opts or {}
  local existing = M.by_root[root]
  if existing and not opts.fresh then
    return cb(existing)
  end
  if not opts.fresh then
    local id = store.active_id(root)
    local iv = id and store.load_interval(root, id)
    if iv and not iv.closed_at and iv.files then
      local t = T.new(root, iv)
      M.by_root[root] = t
      t:reconcile()
      return cb(t)
    end
  end
  M.capture(root, cb)
end

function M.capture(root, cb)
  if M.capturing then
    U.warn("A baseline is already being recorded.")
    return
  end
  M.capturing = true
  local notified = 0
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisAIBaseline", modeline = false, data = { root = root, state = "start" } })
  require("noctis.ai.baseline").capture(root, function(done, total)
    if uv.now() - notified > 400 then
      notified = uv.now()
      U.info(("Recording the baseline… %d / %d files"):format(done, total), { id = "noctis_ai_baseline" })
    end
  end, function(iv)
    M.capturing = false
    local old = M.by_root[root]
    if old then
      old:stop()
    end
    local t = T.new(root, iv)
    M.by_root[root] = t
    local s = iv.stats
    U.info(
      ("Baseline ready: content of %d files recorded (%s), %d files out of scope%s · %d ms"):format(
        s.captured,
        U.human_size(s.bytes),
        s.skipped,
        s.limit_hit and (" · limit: " .. s.limit_hit) or "",
        s.ms
      ),
      { id = "noctis_ai_baseline" }
    )
    vim.api.nvim_exec_autocmds("User", { pattern = "NoctisAIBaseline", modeline = false, data = { root = root, state = "done" } })
    vim.defer_fn(function()
      pcall(store.gc, root, iv.id)
    end, 3000)
    cb(t)
  end)
end

--- Close the active interval and take a new baseline (doesn't touch any files).
function M.new_interval(root, cb)
  local t = M.by_root[root]
  if t then
    t.interval.closed_at = os.time()
    store.save_interval(root, t.interval)
    t:stop()
    M.by_root[root] = nil
  end
  M.capture(root, cb)
end

-- Note files the user saved from NOCTIS; reconcile when focus returns.
local group = vim.api.nvim_create_augroup("noctis_ai_tracker", { clear = true })
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(ev)
    local abs = vim.api.nvim_buf_get_name(ev.buf)
    for _, t in pairs(M.by_root) do
      t:note_self_write(abs)
    end
  end,
})
vim.api.nvim_create_autocmd("FocusGained", {
  group = group,
  callback = function()
    for _, t in pairs(M.by_root) do
      t:reconcile()
    end
  end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    for _, t in pairs(M.by_root) do
      t:stop()
    end
  end,
})

return M
