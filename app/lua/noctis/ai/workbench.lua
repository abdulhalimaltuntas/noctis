-- AI Workbench paneli: oturum sekmeleri, proje yolu, terminal ve
-- "Değişiklikler" görünümü. Geniş ekranda sağ panel, orta genişlikte alt
-- panel, dar ekranda tam alan (sekmeli tek görünüm). Panel kendiliğinden
-- odak almaz; gizlemek süreçleri durdurmaz.
local M = {}

local api = vim.api
local sessions = require("noctis.ai.sessions")
local review = require("noctis.ai.review")

M.win = nil ---@type integer?
M.mode = nil ---@type "right"|"bottom"|"full"|nil
M.current = "changes" ---@type string  oturum kimliği veya "changes"

function M.pick_mode()
  local cfg = require("noctis.config").options.ai.layout
  if cfg ~= "auto" then
    return cfg
  end
  local c, l = vim.o.columns, vim.o.lines
  if c >= 150 then
    return "right"
  elseif c >= 90 and l >= 28 then
    return "bottom"
  end
  return "full"
end

function M.is_visible()
  return M.win ~= nil and api.nvim_win_is_valid(M.win)
end

function M.current_session()
  if M.current ~= "changes" then
    return sessions.get(M.current)
  end
end

function M.current_buf()
  local s = M.current_session()
  if s and api.nvim_buf_is_valid(s.buf) then
    return s.buf
  end
  M.current = "changes"
  local buf = review.ensure_list_buf()
  review.render()
  return buf
end

function _G.NoctisAITabClick(n)
  if n == 0 then
    M.show_view("changes", true)
  else
    for _, s in ipairs(sessions.list) do
      if s.n == n then
        M.show_view(s.id, true)
      end
    end
  end
end

local status_hl = {
  starting = "NoctisAIStatusStart",
  running = "NoctisAIStatusRun",
  exited = "NoctisAIStatusExit",
  failed = "NoctisAIStatusFail",
}

function M.winbar()
  local icons = require("noctis.ui.icons")
  local dot = icons.enabled() and "●" or "*"
  local parts = { "%#NoctisAccent# " .. vim.trim(icons.get().ui.ai) .. " " }
  for _, s in ipairs(sessions.list) do
    local active = M.current == s.id
    local tab = active and "NoctisAITabActive" or "NoctisAITabInactive"
    parts[#parts + 1] = ("%%%d@v:lua.NoctisAITabClick@%%#%s# %d %s "):format(s.n, tab, s.n, s.label)
      .. ("%%#%s#%s %s %%X%%#NoctisPanel# "):format(active and tab or status_hl[s.status], dot, sessions.status_text(s))
  end
  local root = require("noctis.ai").view_root()
  local t = root and require("noctis.ai.tracker").get(root)
  local n = t and vim.tbl_count(t.changes) or 0
  local active = M.current == "changes"
  parts[#parts + 1] = ("%%0@v:lua.NoctisAITabClick@%%#%s# Δ Değişiklikler %d %%X"):format(active and "NoctisAITabActive" or "NoctisAITabInactive", n)
  local running = root and #sessions.running(root) or 0
  if running > 1 then
    parts[#parts + 1] = "%#NoctisWarning# ⚠ " .. running .. " araç aynı ağaçta"
  end
  parts[#parts + 1] = "%#NoctisPanel#%="
  if root then
    parts[#parts + 1] = "%#NoctisAIPath#" .. vim.fn.fnamemodify(root, ":~"):gsub("%%", "%%%%") .. " "
  end
  if M.mode ~= "right" or vim.o.columns >= 170 then
    parts[#parts + 1] = "%#NoctisDim#Ctrl-\\ e: editöre dön · Space a s: geç "
  end
  return table.concat(parts)
end

function M.refresh()
  if M.is_visible() then
    vim.wo[M.win].winbar = M.winbar()
  end
  if M.current == "changes" then
    review.render()
  end
end

local function setup_win(win)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.list = false
  wo.wrap = false
  wo.cursorline = false
  wo.spell = false
  wo.statuscolumn = ""
  wo.winhighlight = "Normal:NoctisPanel,NormalNC:NoctisPanel,WinBar:NoctisPanel,WinBarNC:NoctisPanel,EndOfBuffer:NoctisPanel"
end

local function size_for(mode)
  local cfg = require("noctis.config").options.ai
  if mode == "right" then
    return math.max(60, math.floor(vim.o.columns * cfg.width))
  end
  return math.max(10, math.floor(vim.o.lines * cfg.height))
end

local function float_cfg()
  local top = vim.o.showtabline > 0 and 1 or 0
  return {
    relative = "editor",
    row = top,
    col = 0,
    width = vim.o.columns,
    height = math.max(3, vim.o.lines - top - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)),
    style = "minimal",
    border = "none",
    zindex = 30,
  }
end

---@param opts? {focus?:boolean}
function M.open(opts)
  opts = opts or {}
  local buf = M.current_buf()
  local mode = M.pick_mode()
  if M.is_visible() and M.mode ~= mode then
    M.hide()
  end
  local prev = api.nvim_get_current_win()
  if M.is_visible() then
    api.nvim_win_set_buf(M.win, buf)
  else
    if mode == "full" then
      M.win = api.nvim_open_win(buf, false, float_cfg())
    else
      local cmd = mode == "right" and ("botright vertical " .. size_for(mode) .. "split") or ("botright " .. size_for(mode) .. "split")
      vim.cmd(cmd)
      M.win = api.nvim_get_current_win()
      api.nvim_win_set_buf(M.win, buf)
      if mode == "right" then
        vim.wo[M.win].winfixwidth = true
      else
        vim.wo[M.win].winfixheight = true
      end
    end
    setup_win(M.win)
    M.mode = mode
  end
  M.refresh()
  if opts.focus then
    api.nvim_set_current_win(M.win)
    if vim.bo[buf].buftype == "terminal" then
      vim.cmd("startinsert")
    end
  elseif api.nvim_win_is_valid(prev) then
    api.nvim_set_current_win(prev)
  end
end

function M.show_view(view, focus)
  M.current = view
  M.open({ focus = focus })
end

function M.hide()
  if M.is_visible() then
    local was_current = api.nvim_get_current_win() == M.win
    local normal = vim.tbl_filter(function(w)
      return api.nvim_win_get_config(w).relative == "" and w ~= M.win
    end, api.nvim_tabpage_list_wins(0))
    if M.mode == "full" or #normal > 0 then
      api.nvim_win_close(M.win, true)
    else
      api.nvim_win_call(M.win, function()
        vim.cmd("enew")
      end)
    end
    if was_current then
      require("noctis.ui.layout").focus_editor()
    end
  end
  M.win = nil
end

--- Görünürse odakla; odaktaysa gizle; gizliyse göster (odak almadan).
function M.toggle()
  if not M.is_visible() then
    M.open({ focus = false })
  elseif api.nvim_get_current_win() ~= M.win then
    M.open({ focus = true })
  else
    M.hide()
  end
end

--- Yeni oturum için pencere hazırla (jobstart pencerenin buffer'ını kullanır)
function M.prepare_window()
  if not M.is_visible() then
    M.open({ focus = false })
  end
  return M.win
end

local group = api.nvim_create_augroup("noctis_workbench", { clear = true })
api.nvim_create_autocmd("User", {
  group = group,
  pattern = { "NoctisAISession", "NoctisAIChanges", "NoctisThemeChanged", "NoctisAIBaseline" },
  callback = function()
    M.refresh()
    vim.cmd("redrawstatus")
  end,
})
api.nvim_create_autocmd("User", {
  group = group,
  pattern = "NoctisResized",
  callback = function()
    if not M.is_visible() then
      return
    end
    local mode = M.pick_mode()
    local focused = api.nvim_get_current_win() == M.win
    if mode ~= M.mode then
      M.hide()
      M.open({ focus = focused })
    elseif mode == "full" then
      api.nvim_win_set_config(M.win, float_cfg())
    elseif mode == "right" then
      api.nvim_win_set_width(M.win, size_for(mode))
    else
      api.nvim_win_set_height(M.win, size_for(mode))
    end
  end,
})
api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(ev)
    if M.win and tonumber(ev.match) == M.win then
      M.win = nil
    end
  end,
})

return M
