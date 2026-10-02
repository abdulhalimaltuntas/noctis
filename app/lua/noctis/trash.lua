-- Recoverable delete: files/folders are moved to the trash in the NOCTIS state
-- directory. It doesn't depend on the system trash; it works the same on every platform.
local M = {}

local U = require("noctis.util")
local uv = vim.uv

M.RETENTION_DAYS = 30

local function dir()
  return U.state_dir("trash")
end

local function copy_tree(src, dst)
  local res = vim.system({ "cp", "-a", "--", src, dst }):wait(120000)
  return res.code == 0, res.stderr
end

---@param path string
---@return boolean ok, string? err
function M.move(path)
  path = U.norm(path)
  local st = uv.fs_lstat(path)
  if not st then
    return false, "not found"
  end
  local id = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(uv.hrtime() % 1e6)
  local slot = dir() .. "/" .. id
  vim.fn.mkdir(slot, "p", "0o700")
  local name = vim.fn.fnamemodify(path, ":t")
  local dest = slot .. "/" .. name
  local ok, err = uv.fs_rename(path, dest)
  if not ok then
    -- Different filesystem (EXDEV): copy, then remove the source.
    local cok, cerr = copy_tree(path, dest)
    if not cok then
      vim.fn.delete(slot, "rf")
      return false, tostring(err) .. " / " .. tostring(cerr)
    end
    if vim.fn.delete(path, st.type == "directory" and "rf" or "") ~= 0 then
      return false, "copied but the source could not be removed"
    end
  end
  U.json_write(slot .. "/meta.json", { path = path, name = name, deleted_at = os.time(), type = st.type })
  U.log("INFO", "moved to trash: " .. path .. " -> " .. dest)
  return true
end

---@return {slot:string, path:string, name:string, deleted_at:integer, type:string}[]
function M.list()
  local out = {}
  for name, t in vim.fs.dir(dir()) do
    if t == "directory" then
      local meta = U.json_read(dir() .. "/" .. name .. "/meta.json")
      if meta and meta.path then
        meta.slot = dir() .. "/" .. name
        out[#out + 1] = meta
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.deleted_at or 0) > (b.deleted_at or 0)
  end)
  return out
end

function M.restore(item)
  local src = item.slot .. "/" .. item.name
  local dest = item.path
  if uv.fs_lstat(dest) then
    U.error(("`%s` already exists; restoring never overwrites."):format(vim.fn.fnamemodify(dest, ":~")))
    return false
  end
  vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
  local ok, err = uv.fs_rename(src, dest)
  if not ok then
    local cok = copy_tree(src, dest)
    if not cok then
      U.error("Could not restore: " .. tostring(err))
      return false
    end
  end
  vim.fn.delete(item.slot, "rf")
  U.info("Restored: " .. vim.fn.fnamemodify(dest, ":~:."))
  return true
end

function M.pick()
  local items = M.list()
  if #items == 0 then
    U.info("The trash is empty.")
    return
  end
  vim.ui.select(items, {
    prompt = "Item to restore",
    format_item = function(it)
      return ("%s  %s"):format(os.date("%Y-%m-%d %H:%M", it.deleted_at), vim.fn.fnamemodify(it.path, ":~:."))
    end,
  }, function(it)
    if it then
      M.restore(it)
    end
  end)
end

--- Remove items past the retention period (after startup, in the background).
function M.prune()
  local limit = os.time() - M.RETENTION_DAYS * 86400
  for _, it in ipairs(M.list()) do
    if (it.deleted_at or 0) < limit then
      vim.fn.delete(it.slot, "rf")
    end
  end
end

return M
