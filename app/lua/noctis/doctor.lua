-- Shared checks for `noctis --doctor` and `:checkhealth noctis`.
-- Doesn't depend on plugins (it doesn't load a missing plugin to report it),
-- makes no network requests, starts no AI task and shows no account information.
-- Run directly: NVIM_APPNAME=noctis nvim --headless -l .../doctor.lua
local M = {}

local function has(exe)
  return vim.fn.executable(exe) == 1
end

local function run(cmd, timeout)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(timeout or 5000)
  end)
  if not ok or not res then
    return nil
  end
  return res
end

local function first_line(s)
  return vim.trim((s or ""):match("[^\n]*") or "")
end

---@class noctis.DoctorItem
---@field level "ok"|"warn"|"error"|"info"
---@field msg string
---@field advice? string

---@return {title:string, items:noctis.DoctorItem[]}[]
function M.checks()
  local sections = {}
  local cur
  local function section(title)
    cur = { title = title, items = {} }
    sections[#sections + 1] = cur
  end
  local function add(level, msg, advice)
    cur.items[#cur.items + 1] = { level = level, msg = msg, advice = advice }
  end

  local brand = require("noctis.brand")
  -- ── Core ───────────────────────────────────────────────────────────────
  section("Core")
  local v = vim.version()
  local vs = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-" .. brand.min_nvim) == 1 then
    add("ok", ("Neovim %s (%s)"):format(vs, vim.v.progpath))
  else
    add("error", ("Neovim %s is too old; at least %s is required"):format(vs, brand.min_nvim), "https://github.com/neovim/neovim/releases")
  end
  add("ok", ("%s %s · app: %s"):format(brand.name, brand.version, brand.home))
  add("info", ("NVIM_APPNAME=%s (separate from your regular Neovim config)"):format(vim.env.NVIM_APPNAME or "?"))
  add("info", "config: " .. vim.fn.stdpath("config"))
  add("info", "data:   " .. vim.fn.stdpath("data"))
  add("info", "state:  " .. vim.fn.stdpath("state") .. "  (sessions, undo, AI records, log)")
  add("info", "cache:  " .. vim.fn.stdpath("cache"))

  -- ── User settings ──────────────────────────────────────────────────────
  section("User settings")
  local cfg = require("noctis.config")
  cfg.load()
  if vim.uv.fs_stat(cfg.path) then
    add("ok", "config.lua found: " .. cfg.path)
  else
    add("info", "no config.lua; using defaults (example: " .. brand.home .. "/examples/config.lua)")
  end
  for _, e in ipairs(cfg.errors) do
    add("error", e, "The default is used instead of the invalid value; fix the file.")
  end
  for _, w in ipairs(cfg.warnings) do
    add("warn", w)
  end
  if #cfg.errors == 0 and #cfg.warnings == 0 and vim.uv.fs_stat(cfg.path) then
    add("ok", "Settings are valid")
  end

  -- ── Plugins ────────────────────────────────────────────────────────────
  section("Plugins (per the lockfile)")
  local lockfile = brand.home .. "/lazy-lock.json"
  local lock = require("noctis.util").json_read(lockfile)
  local root = vim.fn.stdpath("data") .. "/lazy"
  if not lock then
    add("error", "could not read lazy-lock.json: " .. lockfile)
  else
    local names = vim.tbl_keys(lock)
    table.sort(names)
    local missing, drift = 0, 0
    for _, name in ipairs(names) do
      local dir = root .. "/" .. name
      if not vim.uv.fs_stat(dir) then
        missing = missing + 1
        add("warn", name .. ": not installed")
      else
        local res = has("git") and run({ "git", "-C", dir, "rev-parse", "HEAD" })
        local head = res and res.code == 0 and first_line(res.stdout) or nil
        if head and head ~= lock[name].commit then
          drift = drift + 1
          add("warn", ("%s: commit differs from the lockfile (%s ≠ %s)"):format(name, head:sub(1, 7), lock[name].commit:sub(1, 7)), "To go back to the lockfile, run :Lazy restore inside NOCTIS")
        end
      end
    end
    if missing == #names then
      add("error", "Plugins are not installed. The editor opens in basic mode.", brand.command .. " --setup (needs network)")
    elseif missing > 0 then
      add("warn", missing .. " plugins missing", brand.command .. " --setup")
    else
      add("ok", ("%d plugins installed%s"):format(#names, drift == 0 and ", matching the lockfile" or ""))
    end
  end

  -- ── Tools ──────────────────────────────────────────────────────────────
  section("External tools")
  local tools = {
    { "git", "error", "Required for the Git summary/diff, plugin install and merging" },
    { "rg", "error", "Required for project search, search & replace and the AI scope scan (ripgrep)" },
    { "fd", "info", "Optional; ripgrep is used otherwise" },
    { "lazygit", "info", "Optional Git UI; the NOCTIS Git summary is used otherwise" },
    { "tree-sitter", "info", "For compiling Tree-sitter parsers (optional; Vim syntax otherwise)" },
  }
  for _, t in ipairs(tools) do
    if has(t[1]) then
      add("ok", ("%s: %s"):format(t[1], vim.fn.exepath(t[1])))
    else
      add(t[2], ("%s not found — %s"):format(t[1], t[3]))
    end
  end
  if not (has("cc") or has("gcc") or has("clang")) then
    add("info", "No C compiler — Tree-sitter parsers can't be installed (optional)")
  end

  -- ── Terminal and appearance ────────────────────────────────────────────
  section("Terminal and appearance")
  local term, colorterm = vim.env.TERM or "?", vim.env.COLORTERM or ""
  add("info", ("TERM=%s COLORTERM=%s"):format(term, colorterm ~= "" and colorterm or "(empty)"))
  if colorterm == "truecolor" or colorterm == "24bit" then
    add("ok", "Truecolor reported")
  else
    add("warn", "Truecolor not reported; Neovim queries the terminal at startup. If unsupported, the 256-color fallback is used.", "Can be forced in config.lua: truecolor = true | false")
  end
  if term == "linux" then
    add("warn", "Linux console: icons and rounded borders fall back to plain characters automatically")
  end
  add("info", ("Icons: %s (a Nerd Font can't be detected reliably; if they don't render, set icons = false)"):format(cfg.options.icons and "on" or "off"))

  -- ── Clipboard ──────────────────────────────────────────────────────────
  section("System clipboard")
  if cfg.options.clipboard == "internal" then
    add("info", "Only NOCTIS registers are used (per settings)")
  elseif vim.fn.has("clipboard") == 1 then
    local ok, name = pcall(vim.fn["provider#clipboard#Executable"])
    add("ok", "Clipboard provider: " .. ((ok and name ~= "") and name or "available"))
  else
    add("warn", "System clipboard is not available; yanked text stays in NOCTIS registers", "Linux: install wl-clipboard (Wayland) or xclip/xsel (X11). Over SSH, use a terminal with OSC 52 support.")
  end

  -- ── Language packs ─────────────────────────────────────────────────────
  section("Language packs")
  local lang = require("noctis.lang")
  lang.setup_path()
  for _, name in ipairs(lang.enabled()) do
    local p, st = lang.packs[name], lang.status(name)
    local parts, missing = {}, {}
    for _, s in ipairs(p.servers) do
      if st.server[s.name] then
        parts[#parts + 1] = s.exe
      else
        missing[#missing + 1] = s.exe .. " (" .. s.hint .. ")"
      end
    end
    for _, f in ipairs(p.formatters) do
      if st.formatter[f.name] then
        parts[#parts + 1] = f.exe
      else
        missing[#missing + 1] = f.exe .. " (" .. f.hint .. ")"
      end
    end
    local np = 0
    for _, ok in pairs(st.parser) do
      if ok then
        np = np + 1
      end
    end
    local ptxt = ("parser %d/%d"):format(np, #p.parsers)
    if #missing == 0 then
      add("ok", ("%s: %s · %s"):format(p.label, table.concat(parts, ", "), ptxt))
    else
      add("info", ("%s: missing → %s · %s"):format(p.label, table.concat(missing, "; "), ptxt), "Inside NOCTIS: :NoctisLang install " .. name)
    end
  end

  -- ── PTY and file watching ──────────────────────────────────────────────
  section("PTY and file watching")
  local okpty, job = pcall(vim.fn.jobstart, { "sh", "-c", "exit 0" }, { pty = true })
  if okpty and job and job > 0 then
    local code = vim.fn.jobwait({ job }, 3000)[1]
    if code == 0 then
      add("ok", "PTYs can be created (real terminal sessions)")
    else
      add("warn", "The PTY process didn't exit as expected (code " .. tostring(code) .. ")")
    end
  else
    add("error", "Could not create a PTY: " .. tostring(job), "The AI and terminal panels won't work")
  end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local h = vim.uv.new_fs_event()
  local seen = false
  local started = h and h:start(tmp, {}, function()
    seen = true
  end)
  if started then
    vim.fn.writefile({ "x" }, tmp .. "/probe")
    vim.wait(1000, function()
      return seen
    end, 20)
    h:stop()
    h:close()
    if seen then
      add("ok", "File watch events are received (per-directory watching)")
    else
      add("warn", "No file watch event arrived; changes are tracked by periodic scans (delayed)")
    end
  else
    add("warn", "Could not start the file watcher; periodic scanning is used")
  end
  vim.fn.delete(tmp, "rf")
  local mw = io.open("/proc/sys/fs/inotify/max_user_watches", "r")
  if mw then
    local n = tonumber(mw:read("*l"))
    mw:close()
    local need = cfg.options.ai.watch.max_dirs
    if n and n < need then
      add("warn", ("inotify watch quota is low (%d < %d)"):format(n, need), "sudo sysctl fs.inotify.max_user_watches=524288")
    elseif n then
      add("ok", ("inotify watch quota: %d"):format(n))
    end
  end

  -- ── AI profiles ────────────────────────────────────────────────────────
  section("AI profiles (no task is started; only --version is queried)")
  local P = require("noctis.ai.profiles")
  local all, order, errors = P.all()
  for _, e in ipairs(errors) do
    add("error", e)
  end
  for _, name in ipairs(order) do
    local p = all[name]
    local exe = P.resolve(p)
    if not exe then
      add("info", ("%s: `%s` not found"):format(p.label, p.cmd[1]), "Install: " .. (p.install or "the tool's documentation"))
    else
      local ver
      if p.version_args then
        local cmd = { exe }
        vim.list_extend(cmd, p.version_args)
        local res = run(cmd, 8000)
        if res and res.code == 0 then
          ver = first_line(res.stdout ~= "" and res.stdout or res.stderr)
        else
          ver = "could not read the version"
        end
      end
      add("ok", ("%s: %s%s"):format(p.label, exe, ver and (" · " .. ver) or ""))
    end
  end
  return sections
end

local symbols = {
  ok = { "✓", "32" },
  warn = { "!", "33" },
  error = { "✗", "31" },
  info = { "·", "36" },
}

--- Terminal output (noctis --doctor)
function M.main()
  local color = vim.env.NO_COLOR == nil
  local out = io.stdout
  local function paint(code, s)
    return color and ("\27[" .. code .. "m" .. s .. "\27[0m") or s
  end
  local counts = { ok = 0, warn = 0, error = 0, info = 0 }
  local brand = require("noctis.brand")
  out:write(paint("1;35", brand.name .. " doctor") .. "\n")
  for _, sec in ipairs(M.checks()) do
    out:write("\n" .. paint("1;36", sec.title) .. "\n")
    for _, it in ipairs(sec.items) do
      counts[it.level] = counts[it.level] + 1
      local sym = symbols[it.level]
      out:write(("  %s %s\n"):format(paint(sym[2], sym[1]), it.msg))
      if it.advice then
        out:write(("      %s %s\n"):format(paint("2", "→"), it.advice))
      end
    end
  end
  out:write(("\nSummary: %d ok, %d warnings, %d errors\n"):format(counts.ok, counts.warn, counts.error))
  out:flush()
  os.exit(counts.error > 0 and 1 or 0)
end

-- When run with `nvim -l doctor.lua`
if _G.arg and type(_G.arg[0]) == "string" and _G.arg[0]:match("doctor%.lua$") then
  local home = vim.env.NOCTIS_HOME or vim.fn.fnamemodify(_G.arg[0], ":p:h:h:h")
  vim.env.NOCTIS_HOME = home
  package.path = home .. "/lua/?.lua;" .. home .. "/lua/?/init.lua;" .. package.path
  vim.opt.rtp:prepend(home)
  M.main()
end

return M
