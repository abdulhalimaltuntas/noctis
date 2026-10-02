-- Typing animation: each character typed in Insert/Replace mode briefly glows
-- with the accent color behind it and fades out (~240 ms). Only the background
-- is animated, so syntax colors stay intact.
--
-- Cost: one InsertCharPre autocmd per keystroke, a single shared timer that
-- runs only while a glow is alive, and at most MAX_LIVE extmarks.
-- Skipped for: macros, pastes/typeahead bursts, big files, special buffers,
-- terminals without truecolor (256-color steps look blocky).
local M = {}

local api, uv = vim.api, vim.uv
local ns = api.nvim_create_namespace("noctis_typing")

M.ns = ns
M.LEVELS = 6
M.STEP_MS = 40
local MAX_LIVE = 48 -- oldest glows are dropped beyond this
local BURST = 24 -- more chars than this in one loop iteration = paste, not typing

local live = {} -- { buf, id, born, lvl }
local pending = {}
local scheduled = false
local timer
local enabled = false

local function group(lvl)
  return "NoctisType" .. lvl
end

local function stop_timer()
  if timer and timer:is_active() then
    timer:stop()
  end
end

local function tick()
  local now = uv.now()
  local keep = {}
  for _, g in ipairs(live) do
    if api.nvim_buf_is_valid(g.buf) then
      local lvl = math.floor((now - g.born) / M.STEP_MS) + 1
      if lvl > M.LEVELS then
        pcall(api.nvim_buf_del_extmark, g.buf, ns, g.id)
      else
        if lvl ~= g.lvl then
          local m = api.nvim_buf_get_extmark_by_id(g.buf, ns, g.id, { details = true })
          if m[1] and m[3] and m[3].end_col then
            pcall(api.nvim_buf_set_extmark, g.buf, ns, m[1], m[2], {
              id = g.id,
              end_row = m[3].end_row,
              end_col = m[3].end_col,
              hl_group = group(lvl),
              priority = 4096,
              strict = false,
            })
            g.lvl = lvl
          end
        end
        keep[#keep + 1] = g
      end
    end
  end
  live = keep
  if #live == 0 then
    stop_timer()
  end
end

local function start_timer()
  timer = timer or uv.new_timer()
  if not timer:is_active() then
    timer:start(M.STEP_MS, M.STEP_MS, vim.schedule_wrap(tick))
  end
end

local function flush()
  scheduled = false
  local batch = pending
  pending = {}
  if not enabled or #batch > BURST then
    return
  end
  local now = uv.now()
  for _, p in ipairs(batch) do
    if api.nvim_buf_is_valid(p.buf) then
      -- The character is inserted after InsertCharPre; confirm it really sits
      -- at the recorded position (textwidth wrapping, abbreviations, …).
      local ok, got = pcall(api.nvim_buf_get_text, p.buf, p.row, p.col, p.row, p.col + #p.ch, {})
      if ok and got[1] == p.ch then
        local id = api.nvim_buf_set_extmark(p.buf, ns, p.row, p.col, {
          end_row = p.row,
          end_col = p.col + #p.ch,
          hl_group = group(1),
          priority = 4096,
          strict = false,
        })
        live[#live + 1] = { buf = p.buf, id = id, born = now, lvl = 1 }
      end
    end
  end
  while #live > MAX_LIVE do
    local g = table.remove(live, 1)
    pcall(api.nvim_buf_del_extmark, g.buf, ns, g.id)
  end
  if #live > 0 then
    start_timer()
  end
end

local function on_char()
  local ch = vim.v.char
  if ch == "" or ch:match("^%s$") or vim.fn.reg_executing() ~= "" then
    return
  end
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" or vim.b[buf].noctis_bigfile then
    return
  end
  local pos = api.nvim_win_get_cursor(0)
  pending[#pending + 1] = { buf = buf, row = pos[1] - 1, col = pos[2], ch = ch }
  if not scheduled then
    scheduled = true
    vim.schedule(flush)
  end
end

--- Remove every glow immediately.
function M.clear()
  for _, g in ipairs(live) do
    if api.nvim_buf_is_valid(g.buf) then
      pcall(api.nvim_buf_del_extmark, g.buf, ns, g.id)
    end
  end
  live, pending = {}, {}
  stop_timer()
end

--- Number of glows currently on screen (used by tests and :checkhealth).
function M.live_count()
  return #live
end

--- Whether the animation is running (switched on and truecolor available).
function M.active()
  return enabled
end

local function install(on)
  local aug = api.nvim_create_augroup("noctis_typing", { clear = true })
  if on then
    api.nvim_create_autocmd("InsertCharPre", { group = aug, callback = on_char })
  end
  -- termguicolors may be detected (or switched) after startup
  api.nvim_create_autocmd("OptionSet", {
    group = aug,
    pattern = "termguicolors",
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
end

--- Re-evaluate on/off (config, toggle command, termguicolors changes).
function M.refresh()
  local on = (require("noctis.config").options.ui.typing_animation and vim.o.termguicolors) and true or false
  if on ~= enabled then
    enabled = on
    if not on then
      M.clear()
    end
    install(on)
  end
end

--- Toggle for the current session (the config file is not modified).
function M.toggle()
  local o = require("noctis.config").options.ui
  o.typing_animation = not o.typing_animation
  M.refresh()
  if o.typing_animation and not vim.o.termguicolors then
    require("noctis.util").warn("Yazma animasyonu truecolor gerektirir; terminal 256 renk modunda.")
  else
    require("noctis.util").info("Yazma animasyonu " .. (o.typing_animation and "açık" or "kapalı"))
  end
end

function M.setup()
  enabled = false
  install(false)
  M.refresh()
end

return M
