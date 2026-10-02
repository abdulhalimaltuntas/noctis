-- İkon ve kenarlık setleri. `icons = false` ile tüm arayüz Nerd Font olmadan
-- eksiksiz çalışır. Linux konsolu (TERM=linux) gibi sınırlı ortamlarda
-- otomatik olarak sade karakterlere dönülür.
local M = {}

local nerd = {
  diag = { error = " ", warn = " ", info = " ", hint = "󰌶 " },
  git = { branch = " ", added = "+", changed = "~", removed = "-" },
  file = { modified = "●", readonly = "", unnamed = "[adsız]" },
  ui = {
    lock = "",
    ai = "󰚩 ",
    term = " ",
    folder = " ",
    file = "󰈔 ",
    search = " ",
    sep = "│",
    dot = "•",
    check = "✓",
    cross = "✗",
    arrow = "›",
    warn = " ",
    conflict = "",
    clock = "󰥔 ",
    session = "󰁯 ",
    help = "󰋖 ",
    new = " ",
    palette = " ",
    project = " ",
    quit = "󰗼 ",
  },
}

local plain = {
  diag = { error = "E", warn = "W", info = "I", hint = "H" },
  git = { branch = "", added = "+", changed = "~", removed = "-" },
  file = { modified = "*", readonly = "RO", unnamed = "[adsız]" },
  ui = {
    lock = "RO",
    ai = "AI ",
    term = "> ",
    folder = "",
    file = "",
    search = "/",
    sep = "|",
    dot = "*",
    check = "ok",
    cross = "x",
    arrow = ">",
    warn = "!",
    conflict = "!!",
    clock = "",
    session = "",
    help = "?",
    new = "+",
    palette = ":",
    project = "",
    quit = "",
  },
}

local function limited_terminal()
  return vim.env.TERM == "linux"
end

function M.enabled()
  local cfg = require("noctis.config").options
  return cfg.icons and not limited_terminal()
end

function M.get()
  return M.enabled() and nerd or plain
end

function M.border_name()
  local b = require("noctis.config").options.borders
  if b == "ascii" or limited_terminal() then
    return "+,-,+,|,+,-,+,|"
  end
  return b
end

--- nvim_open_win için kenarlık tablosu
function M.border()
  local b = M.border_name()
  if b == "rounded" then
    return { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
  elseif b == "single" then
    return { "┌", "─", "┐", "│", "┘", "─", "└", "│" }
  end
  return { "+", "-", "+", "|", "+", "-", "+", "|" }
end

--- Eklenti seçenekleri için kenarlık: adlandırılmış stil veya ASCII'de 8'li tablo
function M.border_opt()
  local b = M.border_name()
  if b:find(",") then
    return M.border()
  end
  return b
end

function M.listchars()
  if limited_terminal() then
    return { tab = "> ", trail = "-", nbsp = "+" }
  end
  return { tab = "» ", trail = "·", nbsp = "␣" }
end

function M.fillchars()
  if M.border_name():find(",") then
    return { eob = " ", vert = "|", horiz = "-", horizup = "+", horizdown = "+", vertleft = "+", vertright = "+", verthoriz = "+", diff = "-" }
  end
  return { eob = " ", vert = "│", diff = "╱", fold = " ", foldopen = "▾", foldclose = "▸" }
end

return M
