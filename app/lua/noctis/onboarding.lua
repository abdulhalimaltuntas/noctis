-- Bir dakikalık rehber. Köşede odak almayan küçük bir panel; adımlar gerçek
-- eylemlerle tamamlanır. İlk açılışta bir kez gösterilir; Space h t ile
-- istenildiği zaman açılır/kapanır.
local M = {}

local api = vim.api
local U = require("noctis.util")

local steps = {
  { text = "Dosya aç: Space f f (veya başlangıçta f)", event = "file" },
  { text = "Yazmaya başla: i  → INSERT modu", event = "InsertEnter" },
  { text = "Normal moda dön: Esc", event = "InsertLeave" },
  { text = "Kaydet: Space f s", event = "BufWritePost" },
  { text = "Komut paletini aç: Space Space", event = "palette" },
  { text = "Güvenli çıkış: Space q q (kaydedilmemişleri sorar)", event = "final" },
}

M.state = nil ---@type {i:integer, buf:integer, win:integer, group:integer}?

local function state_path()
  return U.state_dir() .. "/ui.json"
end

local function mark_done()
  local st = U.json_read(state_path()) or {}
  st.onboarding_done = true
  U.json_write(state_path(), st)
end

local function draw()
  local s = M.state
  if not s or not api.nvim_buf_is_valid(s.buf) then
    return
  end
  local ic = require("noctis.ui.icons").get().ui
  local lines, hls = {}, {}
  for i, st in ipairs(steps) do
    local mark = i < s.i and ic.check or (i == s.i and ic.arrow or " ")
    lines[#lines + 1] = (" %s %d. %s "):format(mark, i, st.text)
    hls[#hls + 1] = i < s.i and "NoctisSuccess" or (i == s.i and "NoctisBold" or "NoctisMuted")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = s.i > #steps and " Hazırsınız! Yardım: Space ?  · kapat: Space h t" or " Atlamak/kapatmak: Space h t "
  hls[#hls + 1] = "NoctisDim"
  hls[#hls + 1] = "NoctisDim"
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  local ns = api.nvim_create_namespace("noctis.onboarding")
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for i, g in ipairs(hls) do
    api.nvim_buf_set_extmark(s.buf, ns, i - 1, 0, { line_hl_group = g })
  end
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local cfg = {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - vim.o.cmdheight - 2,
    col = vim.o.columns - 1,
    width = math.min(width + 1, vim.o.columns - 4),
    height = #lines,
  }
  if s.win and api.nvim_win_is_valid(s.win) then
    api.nvim_win_set_config(s.win, cfg)
  else
    cfg.style = "minimal"
    cfg.focusable = false
    cfg.border = require("noctis.ui.icons").border()
    cfg.title = " Rehber "
    cfg.title_pos = "center"
    cfg.zindex = 40
    cfg.noautocmd = true
    s.win = api.nvim_open_win(s.buf, false, cfg)
    vim.wo[s.win].winhighlight = "Normal:NormalFloat"
  end
end

local function advance(event)
  local s = M.state
  if not s then
    return
  end
  local cur = steps[s.i]
  if cur and cur.event == event then
    s.i = s.i + 1
    if s.i == #steps then
      -- Son adım bilgi amaçlı: çıkmayı denemeden tamamlanır
      s.i = #steps + 1
      mark_done()
    end
    vim.schedule(draw)
  end
end

function M.stop()
  local s = M.state
  if not s then
    return
  end
  pcall(api.nvim_del_augroup_by_id, s.group)
  if s.win and api.nvim_win_is_valid(s.win) then
    api.nvim_win_close(s.win, true)
  end
  M.state = nil
  vim.g.noctis_show_hints = false
  mark_done()
end

function M.start()
  if M.state then
    return M.stop()
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local group = api.nvim_create_augroup("noctis_onboarding", { clear = true })
  M.state = { i = 1, buf = buf, group = group }
  vim.g.noctis_show_hints = true
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" and api.nvim_buf_get_name(ev.buf) ~= "" then
        advance("file")
      end
    end,
  })
  for _, ev in ipairs({ "InsertEnter", "InsertLeave", "BufWritePost" }) do
    api.nvim_create_autocmd(ev, {
      group = group,
      callback = function()
        advance(ev)
      end,
    })
  end
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NoctisPaletteOpened",
    callback = function()
      advance("palette")
    end,
  })
  api.nvim_create_autocmd("VimResized", { group = group, callback = vim.schedule_wrap(draw) })
  -- Zaten bir dosya açıksa ilk adım tamam sayılır
  local cur = api.nvim_get_current_buf()
  if vim.bo[cur].buftype == "" and api.nvim_buf_get_name(cur) ~= "" then
    M.state.i = 2
  end
  draw()
end

--- İlk açılışta (bir kez) rehberi göster
function M.maybe_start()
  if not require("noctis.config").options.welcome or #vim.api.nvim_list_uis() == 0 then
    return
  end
  local st = U.json_read(state_path()) or {}
  if st.onboarding_done then
    return
  end
  vim.schedule(function()
    if vim.o.columns >= 70 and vim.o.lines >= 20 then
      M.start()
    end
  end)
end

return M
