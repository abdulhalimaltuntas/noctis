-- AI CLI oturumları: gerçek PTY (Neovim terminal job). Her oturumun sabit
-- proje kökü, araç etiketi, benzersiz kimliği ve terminal buffer'ı vardır.
-- Panel gizlenince süreç çalışmaya devam eder; durdurma/yeniden başlatma
-- açık kullanıcı eylemleridir.
--
-- Durum yalnız kanıta göre gösterilir:
--   starting  süreç başlatıldı, henüz çıktı yok
--   running   süreç canlı ve çıktı üretti (görevin sürdüğü anlamına GELMEZ)
--   exited    süreç çıktı (kod gösterilir)
--   failed    başlatılamadı (executable yok / 126 / 127)
local M = {}

local U = require("noctis.util")
local api = vim.api

---@class noctis.AISession
---@field id string
---@field n integer
---@field profile string
---@field label string
---@field root string
---@field buf integer
---@field job? integer
---@field status "starting"|"running"|"exited"|"failed"
---@field code? integer
---@field started_at integer
---@field output_at? integer
---@field resumed boolean
---@field error? string

---@type noctis.AISession[]
M.list = {}
local counter = 0

local STATUS_TEXT = {
  starting = "başlatılıyor",
  running = "çalışıyor",
  exited = "çıktı",
  failed = "başlatılamadı",
}

function M.status_text(s)
  local t = STATUS_TEXT[s.status] or s.status
  if s.status == "exited" and s.code then
    t = t .. " (" .. s.code .. ")"
  end
  return t
end

local function emit(s)
  vim.schedule(function()
    api.nvim_exec_autocmds("User", { pattern = "NoctisAISession", modeline = false, data = { id = s.id } })
  end)
end

---@param profile table
---@param root string
---@param win integer terminal buffer'ını gösterecek pencere
---@param opts? {resume?:boolean}
---@return noctis.AISession? session, string? err
function M.start(profile, root, win, opts)
  opts = opts or {}
  local exe = require("noctis.ai.profiles").resolve(profile)
  if not exe then
    return nil, ("`%s` bulunamadı.\nKurulum: %s\nBelgeler: %s"):format(profile.cmd[1], profile.install or "aracın belgelerine bakın", profile.docs or "-")
  end
  local cmd = { exe }
  for i = 2, #profile.cmd do
    cmd[#cmd + 1] = profile.cmd[i]
  end
  if opts.resume then
    if not profile.resume_args then
      return nil, profile.label .. " için doğrulanmış bir devam etme (resume) yeteneği tanımlı değil."
    end
    vim.list_extend(cmd, profile.resume_args)
  end
  counter = counter + 1
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  ---@type noctis.AISession
  local s = {
    id = ("%s-%d"):format(profile.name, counter),
    n = counter,
    profile = profile.name,
    label = profile.label,
    root = root,
    buf = buf,
    status = "starting",
    started_at = os.time(),
    resumed = opts.resume == true,
  }
  vim.b[buf].noctis_ai_session = s.id
  vim.b[buf].noctis_label = profile.label
  vim.b[buf].noctis_panel = true
  api.nvim_win_set_buf(win, buf)
  local env = U.child_env(profile.env)
  local ok, job = pcall(api.nvim_win_call, win, function()
    return vim.fn.jobstart(cmd, {
      term = true,
      cwd = root,
      clear_env = true,
      env = env,
      on_stdout = function()
        if s.status == "starting" then
          s.status = "running"
          emit(s)
        end
        s.output_at = os.time()
      end,
      on_exit = function(_, code)
        s.code = code
        s.status = (code == 126 or code == 127) and "failed" or "exited"
        emit(s)
        -- Süreç bitince kaçırılmış olabilecek değişiklikleri yakala
        vim.schedule(function()
          local t = require("noctis.ai.tracker").get(s.root)
          if t then
            t:reconcile()
          end
        end)
      end,
    })
  end)
  if not ok or not job or job <= 0 then
    s.status = "failed"
    s.error = tostring(job)
    M.list[#M.list + 1] = s
    emit(s)
    return s, "başlatılamadı: " .. tostring(job)
  end
  s.job = job
  M.list[#M.list + 1] = s
  emit(s)
  return s
end

function M.get(id)
  for _, s in ipairs(M.list) do
    if s.id == id then
      return s
    end
  end
end

function M.alive(s)
  return s.job ~= nil and (s.status == "starting" or s.status == "running")
end

function M.running(root)
  local out = {}
  for _, s in ipairs(M.list) do
    if M.alive(s) and (not root or s.root == root) then
      out[#out + 1] = { label = s.label, status = STATUS_TEXT[s.status], id = s.id, root = s.root }
    end
  end
  return out
end

function M.stop(s)
  if M.alive(s) then
    vim.fn.jobstop(s.job)
  end
end

--- Oturumu listeden kaldır (buffer silinir)
function M.remove(s)
  M.stop(s)
  if api.nvim_buf_is_valid(s.buf) then
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
  M.list = vim.tbl_filter(function(x)
    return x ~= s
  end, M.list)
  emit(s)
end

--- Seçimi/bağlamı aracın girişine yapıştır (Enter gönderilmez; kullanıcı gözden geçirip gönderir).
function M.paste(s, text)
  if not M.alive(s) then
    return false
  end
  -- Köşeli parantezli yapıştırma: çok satırlı metin satır satır gönderilmez
  vim.fn.chansend(s.job, "\27[200~" .. text .. "\27[201~")
  return true
end

return M
