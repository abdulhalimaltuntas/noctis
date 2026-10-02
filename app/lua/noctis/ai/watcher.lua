-- File system watcher. libuv fs_event's `recursive` flag isn't supported on
-- Linux (silently ignored; verified on Neovim 0.12.4), so every directory is
-- watched separately and newly created directories are added as events
-- arrive. When the limit is reached (max_dirs or the inotify quota) the rest is
-- tracked by a low-frequency reconcile scan.
-- This module doesn't know which program wrote a file; it only reports the changed path.
local scope = require("noctis.ai.scope")
local uv = vim.uv

---@class noctis.Watcher
---@field root string
---@field handles table<string, uv.uv_fs_event_t>
---@field overflow boolean
---@field errors integer
---@field on_path fun(rel:string)
local W = {}
W.__index = W

local function join(dir, name)
  if dir == "" then
    return name
  end
  return dir .. "/" .. name
end

---@param root string
---@param on_path fun(rel:string)
---@return noctis.Watcher
function W.new(root, on_path)
  local self = setmetatable({ root = root, handles = {}, overflow = false, errors = 0, on_path = on_path, closed = false }, W)
  self:watch_tree("")
  return self
end

function W:watch_dir(rel_dir)
  if self.closed or self.handles[rel_dir] then
    return
  end
  if rel_dir ~= "" and (scope.in_skipped_dir(rel_dir) or scope.user_excluded(rel_dir)) then
    return
  end
  if vim.tbl_count(self.handles) >= require("noctis.config").options.ai.watch.max_dirs then
    self.overflow = true
    return
  end
  local abs = rel_dir == "" and self.root or (self.root .. "/" .. rel_dir)
  local st = uv.fs_lstat(abs)
  if not st or st.type ~= "directory" then
    return -- symbolic links are not watched
  end
  local h = uv.new_fs_event()
  if not h then
    self.overflow = true
    return
  end
  local ok = h:start(abs, {}, function(err, filename)
    if err or not filename then
      return
    end
    local rel = join(rel_dir, filename)
    vim.schedule(function()
      self:event(rel)
    end)
  end)
  if not ok then
    -- ENOSPC: the inotify watch quota is exhausted
    self.errors = self.errors + 1
    self.overflow = true
    pcall(h.close, h)
    return
  end
  self.handles[rel_dir] = h
end

function W:watch_tree(rel_dir)
  self:watch_dir(rel_dir)
  local abs = rel_dir == "" and self.root or (self.root .. "/" .. rel_dir)
  local ok, iter = pcall(vim.fs.dir, abs)
  if not ok then
    return
  end
  for name, t in iter do
    if t == "directory" and not scope.skip_dirs[name] then
      self:watch_tree(join(rel_dir, name))
    end
  end
end

function W:event(rel)
  if self.closed then
    return
  end
  local abs = self.root .. "/" .. rel
  local st = uv.fs_lstat(abs)
  if st and st.type == "directory" then
    if not self.handles[rel] and not scope.in_skipped_dir(rel) then
      -- New directory: start watching it and report the files already inside
      self:watch_tree(rel)
      for name, t in vim.fs.dir(abs, {
        depth = 20,
        skip = function(d)
          return not scope.skip_dirs[vim.fn.fnamemodify(d, ":t")]
        end,
      }) do
        if t == "file" or t == "link" then
          self.on_path(rel .. "/" .. name)
        end
      end
    end
    return
  end
  if not st and self.handles[rel] then
    -- Directory deleted: close child watchers, have everything under it re-checked
    for d, h in pairs(self.handles) do
      if d == rel or d:sub(1, #rel + 1) == rel .. "/" then
        pcall(h.stop, h)
        pcall(h.close, h)
        self.handles[d] = nil
      end
    end
    self.on_path(rel .. "/")
    return
  end
  if scope.in_skipped_dir(rel) then
    return
  end
  self.on_path(rel)
end

function W:stop()
  self.closed = true
  for _, h in pairs(self.handles) do
    pcall(h.stop, h)
    pcall(h.close, h)
  end
  self.handles = {}
end

function W:count()
  return vim.tbl_count(self.handles)
end

return W
