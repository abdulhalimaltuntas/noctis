-- Tema motoru: aktif temayı uygular, değiştirir ve seçimi kalıcı kılar.
-- Truecolor yoksa her renk en yakın xterm-256 rengine eşlenir.
local M = {}

local palettes = require("noctis.theme.palettes")
local tokens = require("noctis.theme.tokens")

M.current = nil ---@type string?
M.tokens = nil ---@type table?

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
--- #RRGGBB -> xterm-256 indeksi (16..255; sistem renklerinden kaçınır)
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
    require("noctis.util").warn(("Bilinmeyen tema `%s`; Midnight Violet kullanılıyor"):format(tostring(name)))
    name = "midnight-violet"
  end
  local t = tokens.derive(palettes[name])
  local groups = require("noctis.theme.highlights").build(t, { transparent = cfg.transparent })

  if vim.g.colors_name then
    vim.cmd("highlight clear")
  end
  vim.o.background = "dark"
  for group, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, group, with_cterm(spec))
  end
  for i, col in ipairs(require("noctis.theme.highlights").terminal_colors(t)) do
    vim.g["terminal_color_" .. (i - 1)] = col
  end
  vim.g.colors_name = name
  M.current, M.tokens = name, t

  if opts.persist then
    local U = require("noctis.util")
    local path = U.state_dir() .. "/ui.json"
    local st = U.json_read(path) or {}
    st.theme = name
    U.json_write(path, st)
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisThemeChanged", modeline = false })
end

--- Tema seçici (önizlemeli): seçim değiştikçe tema anında uygulanır,
--- iptal edilirse önceki temaya dönülür.
function M.pick()
  local before = M.current
  local items = {}
  for _, n in ipairs(palettes.order) do
    items[#items + 1] = n
  end
  vim.ui.select(items, {
    prompt = "Tema seç",
    format_item = function(n)
      return palettes.labels[n] .. (n == before and "  (etkin)" or "")
    end,
  }, function(choice)
    if choice then
      M.apply(choice, { persist = true })
      require("noctis.util").info("Tema: " .. palettes.labels[choice])
    elseif before then
      M.apply(before)
    end
  end)
end

-- Kullanıcının `:colorscheme` ile başka bir şemaya geçmesi meşrudur; NOCTIS
-- bileşen grupları korunur ki arayüz bozulmasın.
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
