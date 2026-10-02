-- Theme engine: applies the active theme, switches it and persists the choice.
-- Without truecolor every color is mapped to the nearest xterm-256 color.
local M = {}

local palettes = require("noctis.theme.palettes")
local tokens = require("noctis.theme.tokens")

M.current = nil ---@type string?
M.tokens = nil ---@type table?
M.last_dark = nil ---@type string? the dark variant to return to from Daybreak

local cube = { 0, 95, 135, 175, 215, 255 }

local function nearest_cube(v)
  local best, bi = math.huge, 1
  for i, c in ipairs(cube) do
    local d = math.abs(c - v)
    if d < best then
      best, bi = d, i
    end
  end
  return bi - 1, cube[bi]
end

local cache = {}
--- #RRGGBB -> xterm-256 index (16..255; avoids the system colors)
function M.to_cterm(hex)
  if cache[hex] then
    return cache[hex]
  end
  local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
  local ri, rv = nearest_cube(r)
  local gi, gv = nearest_cube(g)
  local bi, bv = nearest_cube(b)
  local cidx = 16 + 36 * ri + 6 * gi + bi
  local cd = (r - rv) ^ 2 + (g - gv) ^ 2 + (b - bv) ^ 2
  local avg = (r + g + b) / 3
  local gi2 = math.max(0, math.min(23, math.floor((avg - 8) / 10 + 0.5)))
  local gval = 8 + 10 * gi2
  local gd = (r - gval) ^ 2 + (g - gval) ^ 2 + (b - gval) ^ 2
  local res = gd < cd and (232 + gi2) or cidx
  cache[hex] = res
  return res
end

local function with_cterm(spec)
  if spec.link then
    return spec
  end
  local out = vim.tbl_extend("force", {}, spec)
  if spec.fg and spec.fg ~= "NONE" then
    out.ctermfg = M.to_cterm(spec.fg)
  end
  if spec.bg and spec.bg ~= "NONE" then
    out.ctermbg = M.to_cterm(spec.bg)
  end
  local cterm = {}
  for _, k in ipairs({ "bold", "italic", "underline", "undercurl", "strikethrough", "reverse" }) do
    if spec[k] then
      cterm[k] = true
    end
  end
  if next(cterm) then
    out.cterm = cterm
  end
  return out
end

function M.exists(name)
  return palettes[name] ~= nil and type(palettes[name]) == "table" and palettes[name].bg ~= nil
end

---@param name? string
---@param opts? {persist?:boolean}
function M.apply(name, opts)
  opts = opts or {}
  local cfg = require("noctis.config").options
  name = name or cfg.theme
  if not M.exists(name) then
    require("noctis.util").warn(("Unknown theme `%s`; using Midnight Violet"):format(tostring(name)))
    name = "midnight-violet"
  end
  local t = tokens.derive(palettes[name], { transparent = cfg.transparent })
  local groups = require("noctis.theme.highlights").build(t, { transparent = cfg.transparent })

  if vim.g.colors_name then
    vim.cmd("highlight clear")
  end
  -- `:highlight clear` unlets g:colors_name, so this doesn't re-source the scheme.
  vim.o.background = palettes[name].background or "dark"
  for group, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, group, with_cterm(spec))
  end
  for i, col in ipairs(require("noctis.theme.highlights").terminal_colors(t)) do
    vim.g["terminal_color_" .. (i - 1)] = col
  end
  vim.g.colors_name = name
  M.current, M.tokens = name, t
  if palettes[name].background ~= "light" then
    M.last_dark = name
  end

  if opts.persist then
    local U = require("noctis.util")
    local path = U.state_dir() .. "/ui.json"
    local st = U.json_read(path) or {}
    st.theme = name
    U.json_write(path, st)
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisThemeChanged", modeline = false })
end

--- The dark theme to return to from Daybreak: the last dark one used, else the
--- configured one when it's dark.
function M.dark_default()
  if M.last_dark then
    return M.last_dark
  end
  local want = require("noctis.config").options.theme
  if M.exists(want) and palettes[want].background ~= "light" then
    return want
  end
  return "midnight-violet"
end

--- Entry point for colors/*.lua. Neovim re-sources the active scheme when
--- 'background' changes; then `:set background=light` switches to Daybreak and
--- `:set background=dark` back to the configured dark theme (not persisted).
---@param name string
function M.load(name)
  local p = palettes[name]
  if p and M.current == name and p.background ~= vim.o.background then
    name = vim.o.background == "light" and "daybreak" or M.dark_default()
  end
  M.apply(name)
end

-- ── Contrast audit ───────────────────────────────────────────────────────
-- WCAG 2.x floors: text 4.5:1 (AA); deliberately dim text (line numbers,
-- inlay hints, statusline hints) 3:1; popup borders 2:1 so the popup edge
-- is visible but quiet. Separators, indent guides, whitespace marks and diff
-- filler are decorative and exempt.
local DECOR = {
  "^NoctisPanelBorder$", "^NoctisExplorerBorder$", "^WinSeparator$", "^VertSplit$", "Indent", "^Whitespace$",
  "^EndOfBuffer$", "^SnacksPickerTree$", "^LazyProgressTodo$", "^NoctisStSep$", "^DiffDelete$",
  "DeletePreview$", "^BlinkCmpDocSeparator$",
}
-- Foreground groups that are drawn over another group's background: the
-- matched characters, paths and keys on a selected row. (Visual selection is
-- transient and must stay visible, so it's only checked against the editor fg.)
local OVERLAYS = {
  { "SnacksPickerMatch", "SnacksPickerListCursorLine" },
  { "SnacksPickerDir", "SnacksPickerListCursorLine" },
  { "SnacksPickerFile", "SnacksPickerListCursorLine" },
  { "BlinkCmpLabelMatch", "BlinkCmpMenuSelection" },
  { "BlinkCmpLabelDetail", "BlinkCmpMenuSelection" },
  { "BlinkCmpKind", "BlinkCmpMenuSelection" },
  { "NoctisPaletteKey", "SnacksPickerListCursorLine" },
  { "NoctisPaletteGroup", "SnacksPickerListCursorLine" },
  { "NoctisPaletteDesc", "SnacksPickerListCursorLine" },
  { "NoctisDashKey", "NoctisDashSel" },
  { "NoctisDashDesc", "NoctisDashSel" },
  { "NoctisDashPath", "NoctisDashSel" },
  { "CursorLineNr", "CursorLine" },
  { "Comment", "CursorLine" },
}
-- Text drawn over these backgrounds uses the editor fg; momentary glows are exempt.
local BG_EXEMPT = { "^NoctisType%d$", "^NoctisFlash$", "^TermCursor$", "^Cursor$" }

local function matches(name, pats)
  for _, pat in ipairs(pats) do
    if name:match(pat) then
      return true
    end
  end
  return false
end

---@param name? string theme name (default: every theme)
---@return {theme:string, group:string, ratio:number, min:number, fg:string, bg:string}[] problems
function M.audit(name)
  local names = name and { name } or palettes.order
  local problems = {}
  local hl = require("noctis.theme.highlights")
  for _, n in ipairs(names) do
    local t = tokens.derive(palettes[n])
    local groups = hl.build(t, { transparent = false })
    local function resolve(spec)
      local guard = 0
      while spec and spec.link and guard < 10 do
        spec, guard = groups[spec.link], guard + 1
      end
      return spec or {}
    end
    local function check(group, fg, bg, min)
      local r = tokens.contrast(fg, bg)
      if r < min then
        problems[#problems + 1] = { theme = n, group = group, ratio = r, min = min, fg = fg, bg = bg }
      end
    end
    for group, raw in pairs(groups) do
      local spec = resolve(raw)
      local bg = (spec.bg and spec.bg ~= "NONE") and spec.bg or t.bg
      if spec.fg and spec.fg ~= "NONE" then
        if group:find("Border", 1, true) and not matches(group, DECOR) then
          check(group, spec.fg, bg, 2.0)
        elseif not matches(group, DECOR) then
          check(group, spec.fg, bg, spec.fg == t.fg_dim and 3.0 or 4.5)
        end
      elseif spec.bg and spec.bg ~= "NONE" and not matches(group, BG_EXEMPT) then
        check(group .. " (text over bg)", t.fg, spec.bg, 4.5)
      end
    end
    for _, pair in ipairs(OVERLAYS) do
      local fg, over = resolve(groups[pair[1]]), resolve(groups[pair[2]])
      if fg.fg and over.bg then
        check(("%s over %s"):format(pair[1], pair[2]), fg.fg, over.bg, fg.fg == t.fg_dim and 3.0 or 4.5)
      end
    end
    -- Code can appear on every surface (editor, side panel, hover popups)
    local text = vim.tbl_extend("force", {}, t.syntax, { fg = t.fg, muted = t.muted, punct = t.punct, operator = t.operator })
    for key, fg in pairs(text) do
      for _, surface in ipairs({ "bg", "panel", "float" }) do
        check(("%s on %s"):format(key, surface), fg, t[surface], 4.5)
      end
    end
  end
  table.sort(problems, function(a, b)
    return a.theme == b.theme and a.ratio < b.ratio or a.theme < b.theme
  end)
  return problems
end

--- Theme picker (with preview): the theme applies as the selection changes,
--- and the previous theme comes back if cancelled.
function M.pick()
  local before = M.current
  local items = {}
  for _, n in ipairs(palettes.order) do
    items[#items + 1] = n
  end
  vim.ui.select(items, {
    prompt = "Pick a theme",
    format_item = function(n)
      return palettes.labels[n] .. (n == before and "  (active)" or "")
    end,
  }, function(choice)
    if choice then
      M.apply(choice, { persist = true })
      require("noctis.util").info("Theme: " .. palettes.labels[choice])
    elseif before then
      M.apply(before)
    end
  end)
end

-- Switching to another scheme with `:colorscheme` is legitimate; NOCTIS
-- component groups are kept so the interface doesn't break.
function M.setup()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("noctis_theme", { clear = true }),
    callback = function(ev)
      if M.exists(ev.match) then
        return
      end
      local t = M.tokens
      if not t then
        return
      end
      local groups = require("noctis.theme.highlights").build(t, { transparent = false })
      for group, spec in pairs(groups) do
        if group:match("^Noctis") then
          vim.api.nvim_set_hl(0, group, with_cterm(spec))
        end
      end
      M.current = ev.match
      vim.api.nvim_exec_autocmds("User", { pattern = "NoctisThemeChanged", modeline = false })
    end,
  })
end

return M
