-- Small test helpers (no dependencies). Tests run with NOCTIS loaded via
-- `nvim --headless -u app/init.lua -l tests/lua/<file>.lua`.
local H = { passed = 0, failed = 0, notes = {} }

-- `-l` sets 'verbose' to 1; keep file-write messages out of the test output.
-- Notifications are silenced so they don't mix with the test output (they go to the log).
vim.o.verbose = 0
vim.notify = function(msg, level)
  if level and level >= vim.log.levels.ERROR then
    io.stderr:write("[notify:error] " .. tostring(msg) .. "\n")
  end
end

local function out(s)
  io.stdout:write(s .. "\n")
  io.stdout:flush()
end

function H.suite(name)
  out("\n▸ " .. name)
end

function H.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    H.passed = H.passed + 1
    out("  ✓ " .. name)
  else
    H.failed = H.failed + 1
    out("  ✗ " .. name .. "\n" .. tostring(err):gsub("\n", "\n      "))
  end
end

function H.note(s)
  H.notes[#H.notes + 1] = s
  out("    · " .. s)
end

function H.eq(a, b, msg)
  if a ~= b then
    error(("%s: expected %s, got %s"):format(msg or "not equal", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function H.ok(v, msg)
  if not v then
    error(msg or "condition not met", 2)
  end
  return v
end

function H.wait(ms, cond, msg)
  if not vim.wait(ms, cond, 10) then
    error("timeout (" .. ms .. " ms): " .. (msg or ""), 2)
  end
end

function H.tmpdir(name)
  local d = vim.fn.tempname() .. "-" .. name
  vim.fn.mkdir(d, "p")
  return vim.fs.normalize(vim.uv.fs_realpath(d) or d)
end

function H.write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

function H.read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local d = f:read("*a")
  f:close()
  return d
end

function H.sh(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait(60000)
  return res
end

function H.git(root, ...)
  local res = H.sh(vim.list_extend({ "git", "-C", root }, { ... }))
  if res.code ~= 0 then
    error("git error: " .. table.concat({ ... }, " ") .. "\n" .. (res.stderr or ""), 2)
  end
  return res.stdout
end

function H.init_repo(root)
  H.git(root, "init", "-q")
  H.git(root, "config", "user.email", "test@noctis.local")
  H.git(root, "config", "user.name", "NOCTIS Test")
  H.git(root, "config", "commit.gpgsign", "false")
end

H.home = vim.env.NOCTIS_HOME
H.repo = vim.fn.fnamemodify(H.home, ":h")
H.fake = H.repo .. "/tools/noctis-fake-ai"

--- Run the fake AI CLI in batch mode (a real external process)
function H.fake_batch(root, ...)
  local cmd = { "python3", H.fake, "--batch", ... }
  local res = vim.system(cmd, { cwd = root, text = true }):wait(30000)
  if res.code ~= 0 then
    error("fake-ai error: " .. (res.stdout or "") .. (res.stderr or ""), 2)
  end
  return vim.uv.hrtime()
end

function H.done()
  out(("\n%d passed, %d failed"):format(H.passed, H.failed))
  io.stdout:flush()
  os.exit(H.failed > 0 and 1 or 0)
end

return H
