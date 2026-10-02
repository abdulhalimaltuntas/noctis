-- Shared helpers: notifications, logging, file I/O (atomic writes), JSON, child process environment.
local M = {}

local uv = vim.uv

M.title = "NOCTIS"

---@param msg string
---@param level? integer vim.log.levels
---@param opts? table
function M.notify(msg, level, opts)
  opts = opts or {}
  opts.title = opts.title or M.title
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, opts)
  end)
end

function M.info(msg, opts)
  M.notify(msg, vim.log.levels.INFO, opts)
end
function M.warn(msg, opts)
  M.notify(msg, vim.log.levels.WARN, opts)
end
function M.error(msg, opts)
  M.notify(msg, vim.log.levels.ERROR, opts)
end

---@param sub? string
---@return string
function M.state_dir(sub)
  local dir = vim.fn.stdpath("state") .. "/noctis"
  if sub then
    dir = dir .. "/" .. sub
  end
  vim.fn.mkdir(dir, "p", "0o700")
  return dir
end

local LOG_MAX = 512 * 1024

---@param level string
---@param msg string
function M.log(level, msg)
  local path = vim.fn.stdpath("state") .. "/noctis.log"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local st = uv.fs_stat(path)
  if st and st.size > LOG_MAX then
    pcall(uv.fs_rename, path, path .. ".1")
  end
  local f = io.open(path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S"), " [", level, "] ", msg, "\n")
    f:close()
  end
end

---@param path string
---@return string? data, string? err
function M.read_file(path)
  local fd, err = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, err
  end
  local st = uv.fs_fstat(fd)
  if not st then
    uv.fs_close(fd)
    return nil, "stat failed"
  end
  local data = uv.fs_read(fd, st.size, 0)
  uv.fs_close(fd)
  return data
end

--- Atomic write: write to a temp file in the same directory, fsync, rename.
---@param path string
---@param data string
---@param mode? integer
---@return boolean ok, string? err
function M.write_file(path, data, mode)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local tmp = ("%s/.%s.noctis-%d-%d.tmp"):format(dir, vim.fn.fnamemodify(path, ":t"), uv.os_getpid(), uv.hrtime() % 1e9)
  local fd, err = uv.fs_open(tmp, "w", mode or 420)
  if not fd then
    return false, err
  end
  local ok, werr = uv.fs_write(fd, data, 0)
  if not ok then
    uv.fs_close(fd)
    uv.fs_unlink(tmp)
    return false, werr
  end
  uv.fs_fsync(fd)
  uv.fs_close(fd)
  local rok, rerr = uv.fs_rename(tmp, path)
  if not rok then
    uv.fs_unlink(tmp)
    return false, rerr
  end
  return true
end

---@param path string
---@return table?
function M.json_read(path)
  local data = M.read_file(path)
  if not data or data == "" then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if ok and type(obj) == "table" then
    return obj
  end
  M.log("WARN", "ignored corrupt JSON: " .. path)
  return nil
end

---@param path string
---@param obj table
function M.json_write(path, obj)
  return M.write_file(path, vim.json.encode(obj), 384)
end

---@param exe string
function M.has(exe)
  return vim.fn.executable(exe) == 1
end

--- Environment for child processes (terminals, AI CLIs, tasks).
--- NOCTIS-specific variables are removed and the user's NVIM_APPNAME is restored.
---@param extra? table<string,string>
---@return table<string,string>
function M.child_env(extra)
  local env = vim.fn.environ()
  for k in pairs(env) do
    if k:match("^NOCTIS_") then
      env[k] = nil
    end
  end
  env.NVIM_APPNAME = vim.env.NOCTIS_ORIG_NVIM_APPNAME
  env.NVIM_LISTEN_ADDRESS = nil
  for k, v in pairs(extra or {}) do
    env[k] = v
  end
  return env
end

--- Normalize a path (absolute, no trailing /).
---@param path string
function M.norm(path)
  local p = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if #p > 1 then
    p = p:gsub("/+$", "")
  end
  return p
end

---@param path string
---@param root string
---@return string? rel
function M.relpath(root, path)
  root = M.norm(root)
  path = M.norm(path)
  if path == root then
    return "."
  end
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return nil
end

--- Simple debounce (runs once, `ms` after the last call).
function M.debounce(ms, fn)
  local timer = uv.new_timer()
  local args
  return function(...)
    args = { n = select("#", ...), ... }
    timer:stop()
    timer:start(ms, 0, function()
      vim.schedule(function()
        fn(unpack(args, 1, args.n))
      end)
    end)
  end, timer
end

--- "1 file", "3 files" (plural defaults to word .. "s")
function M.plural(n, word, plural)
  return ("%d %s"):format(n, n == 1 and word or (plural or word .. "s"))
end

function M.human_size(n)
  if n < 1024 then
    return n .. " B"
  elseif n < 1024 * 1024 then
    return ("%.1f KiB"):format(n / 1024)
  end
  return ("%.1f MiB"):format(n / 1024 / 1024)
end

--- Truncate text to a display width.
function M.truncate(s, width)
  if vim.fn.strdisplaywidth(s) <= width then
    return s
  end
  if width <= 1 then
    return "…"
  end
  local out = vim.fn.strcharpart(s, 0, width - 1)
  while vim.fn.strdisplaywidth(out) > width - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. "…"
end

--- Shorten a path from the left: …/dir/file.lua
function M.shorten_path(path, width)
  if vim.fn.strdisplaywidth(path) <= width then
    return path
  end
  local parts = vim.split(path, "/", { plain = true })
  while #parts > 1 do
    table.remove(parts, 1)
    local s = "…/" .. table.concat(parts, "/")
    if vim.fn.strdisplaywidth(s) <= width then
      return s
    end
  end
  return M.truncate(parts[1] or path, width)
end

function M.is_safe_mode()
  return vim.env.NOCTIS_SAFE == "1"
end

return M
