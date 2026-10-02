-- Görevler: run/test/build komutları kullanıcı seçtiğinde çalışır.
-- Proje açılışında hiçbir görev kendiliğinden başlamaz. Projeye ait görev
-- dosyası (.noctis/tasks.json) yalnız Neovim'in güven onayı (vim.secure)
-- verildiyse okunur. Komutlar shell metnine birleştirilmeden argv olarak verilir.
local M = {}

local U = require("noctis.util")
local api = vim.api

---@class noctis.Task
---@field name string
---@field cmd string[]|string
---@field cwd? string
---@field source string

---@class noctis.TaskRun
---@field task noctis.Task
---@field buf integer
---@field job integer
---@field started integer
---@field code? integer
---@field ended? integer

---@type noctis.TaskRun[]
M.runs = {}

local function root()
  return require("noctis.project").root()
end

local function detect(r)
  local out = {}
  -- package.json scripts
  local pkg = U.json_read(r .. "/package.json")
  if pkg and type(pkg.scripts) == "table" then
    local runner = vim.uv.fs_stat(r .. "/pnpm-lock.yaml") and "pnpm" or (vim.uv.fs_stat(r .. "/yarn.lock") and "yarn" or "npm")
    local names = vim.tbl_keys(pkg.scripts)
    table.sort(names)
    for _, name in ipairs(names) do
      out[#out + 1] = { name = name, cmd = { runner, "run", name }, source = runner }
    end
  end
  -- Makefile hedefleri (basit tarama; kural gövdeleri çalıştırılmaz)
  local mk = U.read_file(r .. "/Makefile") or U.read_file(r .. "/makefile")
  if mk then
    local seen = {}
    for target in mk:gmatch("\n([%w][%w_%-%.]*)%s*:[^=]") do
      if not seen[target] and not target:match("^%.") then
        seen[target] = true
        out[#out + 1] = { name = target, cmd = { "make", target }, source = "make" }
      end
    end
    local first = mk:match("^([%w][%w_%-%.]*)%s*:[^=]")
    if first and not seen[first] then
      table.insert(out, { name = first, cmd = { "make", first }, source = "make" })
    end
  end
  if vim.uv.fs_stat(r .. "/Cargo.toml") then
    for _, s in ipairs({ "build", "test", "run" }) do
      out[#out + 1] = { name = s, cmd = { "cargo", s }, source = "cargo" }
    end
  end
  if vim.uv.fs_stat(r .. "/go.mod") then
    out[#out + 1] = { name = "build", cmd = { "go", "build", "./..." }, source = "go" }
    out[#out + 1] = { name = "test", cmd = { "go", "test", "./..." }, source = "go" }
  end
  if vim.uv.fs_stat(r .. "/pyproject.toml") or vim.uv.fs_stat(r .. "/pytest.ini") or vim.uv.fs_stat(r .. "/tests") then
    if U.has("pytest") then
      out[#out + 1] = { name = "test", cmd = { "pytest" }, source = "pytest" }
    end
  end
  return out
end

--- Proje görev dosyası: yalnız kullanıcı güvenirse
local function project_tasks(r)
  local path = r .. "/.noctis/tasks.json"
  if not vim.uv.fs_stat(path) then
    return {}
  end
  local ok, content = pcall(vim.secure.read, path)
  if not ok or not content then
    U.info("Proje görev dosyası güvenilir olarak işaretlenmedi; atlandı (.noctis/tasks.json).")
    return {}
  end
  local dok, data = pcall(vim.json.decode, content)
  if not dok or type(data) ~= "table" then
    U.warn(".noctis/tasks.json okunamadı (geçersiz JSON).")
    return {}
  end
  local out = {}
  for _, t in ipairs(data) do
    if type(t) == "table" and type(t.name) == "string" and (type(t.cmd) == "table" or type(t.cmd) == "string") then
      out[#out + 1] = { name = t.name, cmd = t.cmd, cwd = t.cwd and (r .. "/" .. t.cwd) or nil, source = "proje" }
    end
  end
  return out
end

function M.list()
  local r = root()
  local out = {}
  for _, t in ipairs(require("noctis.config").options.tasks or {}) do
    if type(t) == "table" and t.name and t.cmd then
      out[#out + 1] = { name = t.name, cmd = t.cmd, cwd = t.cwd, source = "ayar" }
    end
  end
  vim.list_extend(out, project_tasks(r))
  vim.list_extend(out, detect(r))
  return out
end

local function cmd_text(cmd)
  return type(cmd) == "table" and table.concat(cmd, " ") or cmd
end

local function winbar(run)
  local status
  if run.code == nil then
    status = "%#NoctisAIStatusRun# çalışıyor "
  elseif run.code == 0 then
    status = ("%%#NoctisSuccess# ✓ çıkış 0 · %.1f sn "):format((run.ended - run.started) / 1e9)
  else
    status = ("%%#NoctisError# ✗ çıkış %d · %.1f sn "):format(run.code, (run.ended - run.started) / 1e9)
  end
  return ("%%#NoctisAccent# görev %%#NoctisBold#%s %%#NoctisMuted#%s %s%%=%%#NoctisDim# Space t x: iptal · Ctrl-\\ e: editöre dön "):format(
    run.task.name,
    cmd_text(run.task.cmd):gsub("%%", "%%%%"),
    status
  )
end

---@param task noctis.Task
function M.run(task)
  local cmd = task.cmd
  if type(cmd) == "string" then
    cmd = { vim.o.shell, vim.o.shellcmdflag, cmd } -- kullanıcı tanımlı shell metni
  end
  if vim.fn.executable(cmd[1]) ~= 1 then
    U.error(("`%s` bulunamadı; görev başlatılamadı."):format(cmd[1]))
    return
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  local term = require("noctis.terminal")
  -- Görev çıktısı terminal panelinde gösterilir
  if term.is_visible() then
    api.nvim_win_set_buf(term.win, buf)
    api.nvim_set_current_win(term.win)
  else
    vim.cmd("botright 12split")
    term.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(term.win, buf)
    vim.wo[term.win].winhighlight = "Normal:NoctisPanel,NormalNC:NoctisPanel,WinBar:NoctisPanel,WinBarNC:NoctisPanel"
  end
  local run = { task = task, buf = buf, started = vim.uv.hrtime() }
  vim.b[buf].noctis_label = "görev: " .. task.name
  vim.b[buf].noctis_panel = true
  local job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = task.cwd or root(),
    clear_env = true,
    env = U.child_env(),
    on_exit = function(_, code)
      run.code, run.ended = code, vim.uv.hrtime()
      vim.schedule(function()
        for _, w in ipairs(vim.fn.win_findbuf(buf)) do
          vim.wo[w].winbar = winbar(run)
        end
        if code == 0 then
          U.info(("Görev tamamlandı: %s (çıkış 0)"):format(task.name))
        else
          U.warn(("Görev başarısız: %s (çıkış %d)"):format(task.name, code))
        end
      end)
    end,
  })
  if job <= 0 then
    U.error("Görev başlatılamadı: " .. cmd_text(task.cmd))
    return
  end
  run.job = job
  M.runs[#M.runs + 1] = run
  vim.wo[term.win].winbar = winbar(run)
  vim.cmd("stopinsert")
end

function M.pick()
  local tasks = M.list()
  if #tasks == 0 then
    U.info("Bu projede görev bulunamadı. config.lua › tasks veya .noctis/tasks.json ile ekleyin.")
    return
  end
  vim.ui.select(tasks, {
    prompt = "Görev çalıştır (" .. vim.fn.fnamemodify(root(), ":~") .. ")",
    format_item = function(t)
      return ("%-14s %-22s %s"):format(t.source, t.name, cmd_text(t.cmd))
    end,
  }, function(t)
    if t then
      M.run(t)
    end
  end)
end

function M.running()
  local out = {}
  for _, r in ipairs(M.runs) do
    if r.code == nil then
      out[#out + 1] = r.task.name
    end
  end
  return out
end

function M.stop()
  local live = vim.tbl_filter(function(r)
    return r.code == nil
  end, M.runs)
  if #live == 0 then
    U.info("Çalışan görev yok.")
    return
  end
  local function kill(r)
    vim.fn.jobstop(r.job)
    U.info("Görev durduruldu: " .. r.task.name)
  end
  if #live == 1 then
    if vim.fn.confirm(("`%s` durdurulsun mu?"):format(live[1].task.name), "&Evet\n&Hayır", 2) == 1 then
      kill(live[1])
    end
    return
  end
  vim.ui.select(live, {
    prompt = "Durdurulacak görev",
    format_item = function(r)
      return r.task.name .. "  " .. cmd_text(r.task.cmd)
    end,
  }, function(r)
    if r then
      kill(r)
    end
  end)
end

return M
