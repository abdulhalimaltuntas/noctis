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
---@param opts? {transparent?:boolean}
function M.derive(p, opts)
  opts = opts or {}
  local b = M.blend
  local t = vim.deepcopy(p)
  -- Two optional palette knobs keep one set of formulas valid on both grounds:
  -- a light ground shows a tint more strongly than a dark one (`tint` scales
  -- every background tint), and dim text needs more weight there (`dim`).
  local k = p.tint or 1
  local function tint(fg, alpha, over)
    return b(fg, over or p.bg, alpha * k)
  end
  t.fg_dim = b(p.muted, p.bg, p.dim or 0.62) -- line numbers, subtle hints
  t.fg_subtle = b(p.fg, p.bg, 0.85)
  -- Code punctuation sits between muted and fg, so brackets and delimiters
  -- don't share the grey of inactive UI chrome; operators get a faint accent2 tint.
  t.punct = b(p.fg, p.muted, 0.30)
  t.operator = b(p.accent2, t.punct, 0.22)
  -- Popup borders: visible against the float fill (the base `border` is for
  -- separators, where a near-invisible line is the point).
  t.border_float = b(p.muted, p.float, 0.46)
  if opts.transparent then
    -- The terminal's own background shows through, so a 4.5% neutral band
    -- (tuned against our bg) can turn into a dark hole. A faint accent tint
    -- reads as a highlight on any background.
    t.cursorline = tint(p.accent, 0.10)
  else
    t.cursorline = b(p.fg, p.bg, 0.045)
  end
  t.panel_cursor = tint(p.accent, 0.16, p.panel)
  t.visual = tint(p.accent, 0.26)
  t.search = tint(p.warning, 0.30)
  t.cursearch = p.warning
  t.match = tint(p.accent2, 0.22)
  t.diff_add = tint(p.success, 0.14)
  t.diff_add_text = tint(p.success, 0.30)
  t.diff_del = tint(p.error, 0.14)
  t.diff_del_text = tint(p.error, 0.30)
  t.diff_change = tint(p.syntax.type, 0.11)
  t.diff_text = tint(p.syntax.type, 0.26)
  t.err_bg = tint(p.error, 0.10)
  t.warn_bg = tint(p.warning, 0.10)
  t.info_bg = tint(p.accent2, 0.08)
  t.hint_bg = tint(p.accent, 0.08)
  t.ok_bg = tint(p.success, 0.10)
  -- Selected row in menus and pickers: strong enough to find at a glance, light
  -- enough that muted paths and descriptions on it still pass AA. Not scaled
  -- by `tint`: on a light ground the hue already carries the selection.
  t.accent_bg = b(p.accent, p.float, 0.14)
  t.accent_soft = b(p.accent, p.bg, 0.55)
  t.accent_hi = b(p.accent, p.fg, 0.72) -- accent text that must stay readable over a selected row
  t.info = p.accent2
  t.hint = b(p.accent, p.fg, 0.7)
  t.flash = tint(p.accent2, 0.18) -- highlight for lines changed externally
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
