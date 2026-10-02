-- Başlangıç kaydı: kapsamdaki metin dosyalarının o anki DİSK içeriği
-- (yalnız hash değil) ve Git durumu. Git'te hiçbir şey değiştirilmez:
-- branch/index/stash/çalışma ağacına dokunulmaz; durum okumaları
-- `--no-optional-locks` ile yapılır (index yenilemesi yazılmaz).
-- Kayıt arayüzü bloklamadan parça parça alınır.
local M = {}

local U = require("noctis.util")
local store = require("noctis.ai.store")
local scope = require("noctis.ai.scope")
local uv = vim.uv

M.MAX_TRACKED = 50000 -- metaveri izlenen en fazla dosya

local function git(root, args)
  local cmd = { "git", "--no-optional-locks", "-C", root }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true, env = { GIT_OPTIONAL_LOCKS = "0" } }):wait(15000)
  return res.code == 0 and res.stdout or nil
end

--- Git anlık durumu (salt okunur)
function M.git_state(root)
  if not U.has("git") then
    return nil
  end
  local top = git(root, { "rev-parse", "--show-toplevel" })
  if not top then
    return nil
  end
  local st = { toplevel = vim.trim(top) }
  st.head = vim.trim(git(root, { "rev-parse", "--verify", "-q", "HEAD" }) or "")
  st.branch = vim.trim(git(root, { "rev-parse", "--abbrev-ref", "HEAD" }) or "")
  local raw = git(root, { "status", "--porcelain=v1", "-z", "--untracked-files=all" }) or ""
  st.entries = {}
  local parts = vim.split(raw, "\0", { plain = true })
  local i = 1
  while i <= #parts do
    local p = parts[i]
    if #p > 3 then
      local x, y, path = p:sub(1, 1), p:sub(2, 2), p:sub(4)
      st.entries[#st.entries + 1] = { x = x, y = y, path = path }
      if x == "R" or x == "C" then
        i = i + 1
      end
    end
    i = i + 1
  end
  return st
end

local function new_id()
  return os.date("%Y%m%d-%H%M%S") .. "-" .. string.format("%04x", uv.hrtime() % 65536)
end

--- Bir dosyanın metaverisini/içeriğini kayda al.
---@return table entry
function M.capture_file(root, rel, budget)
  local cfg = require("noctis.config").options.ai.baseline
  local abs = root .. "/" .. rel
  local st = uv.fs_lstat(abs)
  if not st then
    return nil
  end
  local e = { size = st.size, mtime = st.mtime.sec, nsec = st.mtime.nsec, ino = st.ino, mode = st.mode % 4096 }
  if st.type == "link" then
    e.reason = "symlink"
    return e
  elseif st.type ~= "file" then
    return nil
  end
  if scope.user_excluded(rel) then
    e.reason = "excluded"
  elseif scope.is_sensitive(rel) then
    e.reason = "sensitive"
  elseif st.size > cfg.max_file_size then
    e.reason = "large"
  elseif budget.count >= cfg.max_files then
    e.reason = "limit"
    budget.limit_hit = budget.limit_hit or ("dosya sayısı sınırı (" .. cfg.max_files .. ")")
  elseif budget.bytes + st.size > cfg.max_total_size then
    e.reason = "limit"
    budget.limit_hit = budget.limit_hit or ("toplam boyut sınırı (" .. U.human_size(cfg.max_total_size) .. ")")
  else
    local data = U.read_file(abs)
    if not data then
      e.reason = "unreadable"
    else
      e.hash = store.put_blob(root, data)
      e.binary = scope.is_binary(data) or nil
      budget.count = budget.count + 1
      budget.bytes = budget.bytes + #data
    end
  end
  return e
end

--- Başlangıç kaydını asenkron al.
---@param root string
---@param on_progress? fun(done:integer, total:integer)
---@param on_done fun(interval:table)
function M.capture(root, on_progress, on_done)
  local started = uv.hrtime()
  local files, method = scope.list_files(root)
  local interval = {
    version = 1,
    id = new_id(),
    root = root,
    created_at = os.time(),
    method = method,
    git = M.git_state(root),
    files = {},
    reviewed = {},
    stats = {},
  }
  local budget = { count = 0, bytes = 0 }
  local total = math.min(#files, M.MAX_TRACKED)
  if #files > M.MAX_TRACKED then
    budget.limit_hit = ("izlenen dosya sınırı (%d / %d)"):format(M.MAX_TRACKED, #files)
  end
  local i = 0
  local function step()
    local t0 = uv.hrtime()
    while i < total do
      i = i + 1
      local rel = files[i]
      local e = M.capture_file(root, rel, budget)
      if e then
        interval.files[rel] = e
      end
      -- Her ~12 ms'de bir arayüze nefes aldır
      if (uv.hrtime() - t0) > 12e6 then
        if on_progress then
          on_progress(i, total)
        end
        return vim.defer_fn(step, 1)
      end
    end
    local skipped = 0
    for _, e in pairs(interval.files) do
      if e.reason then
        skipped = skipped + 1
      end
    end
    interval.stats = {
      listed = #files,
      tracked = total,
      captured = budget.count,
      skipped = skipped,
      bytes = budget.bytes,
      limit_hit = budget.limit_hit,
      ms = math.floor((uv.hrtime() - started) / 1e6),
    }
    store.save_interval(root, interval)
    store.set_active(root, interval.id)
    on_done(interval)
  end
  step()
end

return M
