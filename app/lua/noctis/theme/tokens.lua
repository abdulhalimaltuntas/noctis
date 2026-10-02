-- Derives semantic design tokens from the base palette.
local M = {}

local function hex2rgb(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

local function rgb2hex(r, g, b)
  local function c(x)
    return math.max(0, math.min(255, math.floor(x + 0.5)))
  end
  return ("#%02X%02X%02X"):format(c(r), c(g), c(b))
end

--- Blend the fg color over bg with the given alpha.
function M.blend(fg, bg, alpha)
  local r1, g1, b1 = hex2rgb(fg)
  local r2, g2, b2 = hex2rgb(bg)
  return rgb2hex(r1 * alpha + r2 * (1 - alpha), g1 * alpha + g2 * (1 - alpha), b1 * alpha + b2 * (1 - alpha))
end

--- WCAG relative luminance
function M.luminance(hex)
  local function ch(v)
    v = v / 255
    return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
  end
  local r, g, b = hex2rgb(hex)
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end

function M.contrast(a, b)
  local la, lb = M.luminance(a), M.luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

---@param p table base palette from palettes.lua
function M.derive(p)
  local b = M.blend
  local t = vim.deepcopy(p)
  t.fg_dim = b(p.muted, p.bg, 0.62) -- line numbers, subtle hints
  t.fg_subtle = b(p.fg, p.bg, 0.85)
  t.cursorline = b(p.fg, p.bg, 0.045)
  t.panel_cursor = b(p.accent, p.panel, 0.16)
  t.visual = b(p.accent, p.bg, 0.26)
  t.search = b(p.warning, p.bg, 0.30)
  t.cursearch = p.warning
  t.match = b(p.accent2, p.bg, 0.22)
  t.diff_add = b(p.success, p.bg, 0.14)
  t.diff_add_text = b(p.success, p.bg, 0.30)
  t.diff_del = b(p.error, p.bg, 0.14)
  t.diff_del_text = b(p.error, p.bg, 0.30)
  t.diff_change = b(p.syntax.type, p.bg, 0.11)
  t.diff_text = b(p.syntax.type, p.bg, 0.26)
  t.err_bg = b(p.error, p.bg, 0.10)
  t.warn_bg = b(p.warning, p.bg, 0.10)
  t.info_bg = b(p.accent2, p.bg, 0.08)
  t.hint_bg = b(p.accent, p.bg, 0.08)
  t.ok_bg = b(p.success, p.bg, 0.10)
  t.accent_bg = b(p.accent, p.float, 0.22)
  t.accent_soft = b(p.accent, p.bg, 0.55)
  t.info = p.accent2
  t.hint = b(p.accent, p.fg, 0.7)
  t.flash = b(p.accent2, p.bg, 0.18) -- highlight for lines changed externally
  t.ws = b(p.muted, p.bg, 0.30) -- visible whitespace characters
  t.indent = b(p.border, p.bg, 0.75) -- indent guides
  -- Typing animation steps (ease-out); same count as LEVELS in typing.lua
  t.type_glow = {}
  for i, a in ipairs({ 0.50, 0.38, 0.28, 0.19, 0.12, 0.06 }) do
    t.type_glow[i] = b(p.accent, t.cursorline, a)
  end
  return t
end

return M
