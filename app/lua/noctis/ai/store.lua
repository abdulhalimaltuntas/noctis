-- Local store for review records.
-- Location: stdpath("state")/noctis/ai/<project-key>/  (outside the project, 0700)
--   blobs/<sha256>          content (content-addressed, deduplicated)
--   intervals/<id>.json     baseline manifest + review state
--   active.json             the project's active interval
-- Retention time and total size are limited (config: ai.retention_days, ai.max_store_mb).
local M = {}

local U = require("noctis.util")
local uv = vim.uv

function M.key(root)
  return vim.fn.sha256(root):sub(1, 16)
end

--- Path without creating the directory (for reads/checks only)
function M.path(root)
  return vim.fn.stdpath("state") .. "/noctis/ai/" .. M.key(root)
end

function M.dir(root, sub)
  local d = U.state_dir("ai") .. "/" .. M.key(root)
  if sub then
    d = d .. "/" .. sub
  end
  vim.fn.mkdir(d, "p", "0o700")
  return d
end

function M.hash(data)
  return vim.fn.sha256(data)
end

--- Store content, return its hash
function M.put_blob(root, data)
  local h = M.hash(data)
  local path = M.dir(root, "blobs") .. "/" .. h
  if not uv.fs_stat(path) then
    U.write_file(path, data, 384)
  end
  return h
end

function M.get_blob(root, hash)
  if not hash then
    return nil
  end
  return U.read_file(M.dir(root, "blobs") .. "/" .. hash)
end

function M.save_interval(root, interval)
  U.json_write(M.dir(root, "intervals") .. "/" .. interval.id .. ".json", interval)
end

function M.load_interval(root, id)
  return U.json_read(M.dir(root, "intervals") .. "/" .. id .. ".json")
end

function M.active_id(root)
  local a = U.json_read(M.path(root) .. "/active.json")
  return a and a.id or nil
end

function M.set_active(root, id)
  U.json_write(M.dir(root) .. "/active.json", { id = id, root = root, at = os.time() })
end

--- Clean up old intervals and orphaned blobs (called in the background).
function M.gc(root, keep_id)
  local cfg = require("noctis.config").options.ai
  local idir = M.dir(root, "intervals")
  local limit = os.time() - cfg.retention_days * 86400
  local intervals = {}
  for name in vim.fs.dir(idir) do
    local id = name:match("^(.*)%.json$")
    if id then
      local st = uv.fs_stat(idir .. "/" .. name)
      intervals[#intervals + 1] = { id = id, mtime = st and st.mtime.sec or 0 }
    end
  end
  table.sort(intervals, function(a, b)
    return a.mtime > b.mtime
  end)
  local referenced = {}
  local kept = {}
  for _, it in ipairs(intervals) do
    if it.id ~= keep_id and it.mtime < limit then
      os.remove(idir .. "/" .. it.id .. ".json")
    else
      kept[#kept + 1] = it
    end
  end
  for _, it in ipairs(kept) do
    local data = M.load_interval(root, it.id)
    for _, f in pairs(data and data.files or {}) do
      if f.hash then
        referenced[f.hash] = true
      end
    end
  end
  local bdir = M.dir(root, "blobs")
  local total = 0
  local blobs = {}
  for name in vim.fs.dir(bdir) do
    local p = bdir .. "/" .. name
    if not referenced[name] then
      os.remove(p)
    else
      local st = uv.fs_stat(p)
      total = total + (st and st.size or 0)
      blobs[#blobs + 1] = name
    end
  end
  -- If the size limit is exceeded, drop the oldest intervals (except the active one)
  if total > cfg.max_store_mb * 1024 * 1024 and #kept > 1 then
    local oldest = kept[#kept]
    if oldest.id ~= keep_id then
      os.remove(idir .. "/" .. oldest.id .. ".json")
      return M.gc(root, keep_id)
    end
  end
  return total
end

return M
