-- Entegre terminal paneli: proje kökünde gerçek PTY shell oturumları.
-- Panel gizlenince süreç çalışmaya devam eder; yeniden açılınca aynı oturuma
-- dönülür. Kapatma (Space b d) çalışan süreç için onay ister.
local M = {}

local U = require("noctis.util")
local api = vim.api

---@class noctis.Term
---@field buf integer
---@field job integer
---@field label string
---@field cwd string
---@field exited? integer

---@type noctis.Term[]
M.terms = {}
M.current = nil ---@type noctis.Term?
M.win = nil ---@type integer?

local function valid(t)
  return t and api.nvim_buf_is_valid(t.buf)
end

local function prune()
  M.terms = vim.tbl_filter(valid, M.terms)
  if M.current and not valid(M.current) then
    M.current = M.terms[#M.terms]
  end
end

local function winbar()
  local parts = {}
  for i, t in ipairs(M.terms) do
    local active = t == M.current
    local status = t.exited and ("  [çıktı " .. t.exited .. "]") or ""
    parts[#parts + 1] = (active and "%#NoctisAITabActive#" or "%#NoctisAITabInactive#") .. " " .. i .. " " .. t.label .. status .. " "
  end
  return table.concat(parts, "%#NoctisPanel# ") .. "%#NoctisPanel#%=%#NoctisDim# Ctrl-\\ e: editöre dön · Space t t: gizle "
end

function M.refresh_winbar()
  if M.win and api.nvim_win_is_valid(M.win) then
    vim.wo[M.win].winbar = winbar()
  end
end

local function panel_height()
  local lines = vim.o.lines
  return math.max(6, math.min(math.floor(lines * 0.30), 20))
end

function M.is_visible()
  return M.win ~= nil and api.nvim_win_is_valid(M.win)
end

local function open_window(buf)
  if M.is_visible() then
    api.nvim_win_set_buf(M.win, buf)
    api.nvim_set_current_win(M.win)
    return
  end
  vim.cmd("botright " .. panel_height() .. "split")
  M.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(M.win, buf)
  vim.wo[M.win].winfixheight = true
  vim.wo[M.win].winhighlight = "Normal:NoctisPanel,NormalNC:NoctisPanel,WinBar:NoctisPanel,WinBarNC:NoctisPanel"
end

---@param opts? {cmd?:string[], label?:string, cwd?:string}
function M.new(opts)
  opts = opts or {}
  local cwd = opts.cwd or require("noctis.project").root()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  open_window(buf)
  local t = { buf = buf, label = opts.label or ("shell " .. (#M.terms + 1)), cwd = cwd }
  vim.b[buf].noctis_label = t.label
  vim.b[buf].noctis_panel = true
  local cmd = opts.cmd or { vim.o.shell }
  local job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = cwd,
    clear_env = true,
    env = U.child_env(),
    on_exit = function(_, code)
      t.exited = code
      vim.schedule(M.refresh_winbar)
    end,
  })
  if job <= 0 then
    U.error(("Terminal başlatılamadı: %s"):format(table.concat(cmd, " ")))
    api.nvim_buf_delete(buf, { force = true })
    return
  end
  t.job = job
  M.terms[#M.terms + 1] = t
  M.current = t
  M.refresh_winbar()
  vim.cmd("startinsert")
  return t
end

function M.show()
  prune()
  if not M.current then
    return M.new()
  end
  open_window(M.current.buf)
  M.refresh_winbar()
  vim.cmd("startinsert")
end

function M.hide()
  if M.is_visible() then
    -- Pencereyi kapat; buffer ve süreç yaşamaya devam eder
    local others = vim.tbl_filter(function(w)
      return w ~= M.win and api.nvim_win_get_config(w).relative == ""
    end, api.nvim_tabpage_list_wins(0))
    if #others > 0 then
      api.nvim_win_close(M.win, true)
    else
      api.nvim_win_call(M.win, function()
        vim.cmd("enew")
      end)
    end
  end
  M.win = nil
end

function M.toggle()
  if M.is_visible() then
    if api.nvim_get_current_win() == M.win then
      M.hide()
      require("noctis.ui.layout").focus_editor()
    else
      api.nvim_set_current_win(M.win)
      vim.cmd("startinsert")
    end
  else
    M.show()
  end
end

function M.pick()
  prune()
  if #M.terms == 0 then
    return M.new()
  end
  vim.ui.select(M.terms, {
    prompt = "Terminal",
    format_item = function(t)
      return t.label .. (t.exited and (" (çıktı: " .. t.exited .. ")") or "") .. "  " .. vim.fn.fnamemodify(t.cwd, ":~")
    end,
  }, function(t)
    if t then
      M.current = t
      M.show()
    end
  end)
end

--- Çıkış özeti için çalışan shell'ler
function M.running()
  prune()
  local out = {}
  for _, t in ipairs(M.terms) do
    if not t.exited then
      out[#out + 1] = t.label .. " (" .. vim.fn.fnamemodify(t.cwd, ":~") .. ")"
    end
  end
  return out
end

-- Pencere dışarıdan kapatılırsa (ör. :q) kaydı temizle
api.nvim_create_autocmd("WinClosed", {
  group = api.nvim_create_augroup("noctis_terminal", { clear = true }),
  callback = function(ev)
    if M.win and tonumber(ev.match) == M.win then
      M.win = nil
    end
  end,
})

return M
