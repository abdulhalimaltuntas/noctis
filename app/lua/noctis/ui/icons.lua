-- Icon and border sets. With `icons = false` the whole interface works fully
-- without a Nerd Font. In limited environments such as the Linux console
-- (TERM=linux) it falls back to plain characters automatically.
local M = {}

local nerd = {
  diag = { error = " ", warn = " ", info = " ", hint = "󰌶 " },
  git = { branch = " ", added = "+", changed = "~", removed = "-" },
  file = { modified = "●", readonly = "", unnamed = "[No Name]" },
  ui = {
    lock = "",
    ai = "󰚩 ",
    term = " ",
    folder = " ",
    file = "󰈔 ",
    search = " ",
    sep = "│",
    dot = "•",
    check = "✓",
    cross = "✗",
    arrow = "›",
    warn = " ",
    conflict = "",
    clock = "󰥔 ",
    session = "󰁯 ",
    help = "󰋖 ",
    new = " ",
    palette = " ",
    project = " ",
    quit = "󰗼 ",
    settings = " ",
  },
  -- One glyph per command group (palette rows, dashboard actions)
  groups = {
    AI = "󰚩 ",
    Buffer = " ",
    Code = " ",
    Diagnostics = " ",
    File = "󰈔 ",
    General = " ",
    Git = " ",
    Interface = " ",
    Project = " ",
    ["Quit / Session"] = "󰁯 ",
    ["Search / Replace"] = " ",
    Terminal = " ",
    Window = " ",
  },
}

local plain = {
  diag = { error = "E", warn = "W", info = "I", hint = "H" },
  git = { branch = "", added = "+", changed = "~", removed = "-" },
  file = { modified = "*", readonly = "RO", unnamed = "[No Name]" },
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
    settings = "",
  },
  groups = {}, -- no glyph column without a Nerd Font
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

--- Glyph and highlight group for a command group ("" when icons are off).
---@param group string
---@return string icon, string hl
function M.group(group)
  local icon = M.get().groups[group] or (M.enabled() and "• " or "")
  return icon, "NoctisGroup" .. group:gsub("[^%w]", "")
end

function M.border_name()
  local b = require("noctis.config").options.borders
  if b == "ascii" or limited_terminal() then
    return "+,-,+,|,+,-,+,|"
  end
  return b
end

--- Border table for nvim_open_win
function M.border()
  local b = M.border_name()
  if b == "rounded" then
    return { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
  elseif b == "single" then
    return { "┌", "─", "┐", "│", "┘", "─", "└", "│" }
  end
  return { "+", "-", "+", "|", "+", "-", "+", "|" }
end

--- Border for plugin options: a named style, or an 8-item table for ASCII
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
