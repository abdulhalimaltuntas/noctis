-- Editor options. Neovim's mature defaults are kept; only what the product
-- experience needs is changed.
local M = {}

function M.setup()
  local cfg = require("noctis.config").options
  local icons = require("noctis.ui.icons")
  local o, opt, g = vim.o, vim.opt, vim.g

  g.mapleader = " "
  g.maplocalleader = "\\"

  -- Disable unused language providers (startup time and checkhealth noise)
  g.loaded_perl_provider = 0
  g.loaded_ruby_provider = 0
  g.loaded_node_provider = 0
  g.loaded_python3_provider = 0

  -- The file explorer comes from a plugin; in safe mode netrw stays as the built-in explorer.
  if not require("noctis.util").is_safe_mode() then
    g.loaded_netrw = 1
    g.loaded_netrwPlugin = 1
  end

  if cfg.truecolor == true then
    o.termguicolors = true
  elseif cfg.truecolor == false then
    o.termguicolors = false
  end -- "auto": Neovim's terminal detection (COLORTERM / XTGETTCAP) applies

  o.number = true
  o.relativenumber = cfg.ui.relative_numbers
  o.signcolumn = "yes"
  o.cursorline = cfg.ui.cursorline
  o.cursorlineopt = "number,line"
  o.wrap = cfg.ui.wrap
  o.linebreak = true
  o.breakindent = true
  o.scrolloff = 6
  o.sidescrolloff = 8
  o.smoothscroll = true

  o.mouse = "a"
  o.mousemodel = "extend"
  o.ignorecase = true
  o.smartcase = true
  o.inccommand = "split"
  o.grepprg = "rg --vimgrep --smart-case"
  o.grepformat = "%f:%l:%c:%m"

  o.expandtab = true
  o.shiftwidth = 2
  o.tabstop = 2
  o.softtabstop = 2
  o.shiftround = true
  o.smartindent = true

  o.splitright = true
  o.splitbelow = true
  o.splitkeep = "screen"
  o.virtualedit = "block"
  o.jumpoptions = "view"

  -- Data safety: persistent undo, swap (crash recovery), external change detection.
  o.undofile = true
  o.undolevels = 10000
  o.swapfile = true
  o.autoread = true
  o.confirm = true -- ask on close/quit with unsaved buffers instead of failing
  o.fixendofline = false -- don't touch the file's existing final-newline style
  o.updatetime = 250
  o.timeoutlen = 400
  o.ttimeoutlen = 10

  o.laststatus = 3
  o.showmode = false
  -- Pending keys (d2, "a, …) show in the statusline: the last row stays the
  -- message area, and nothing is left behind there when `:` opens the popup.
  o.showcmdloc = "statusline"
  o.showtabline = 2
  o.cmdheight = 1
  o.pumheight = 12
  o.pumblend = 0
  o.winblend = 0
  o.wildmode = "longest:full,full"
  o.completeopt = "menu,menuone,noselect,popup"
  o.shortmess = o.shortmess .. "IcW"
  o.title = true
  o.titlestring = "%{v:lua.require'noctis.ui.statusline'.title()}"

  o.list = true
  opt.listchars = icons.listchars()
  opt.fillchars = icons.fillchars()
  o.winborder = icons.border_name()

  o.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize"
  o.foldlevel = 99
  o.foldlevelstart = 99

  -- Diagnostics are conveyed with a letter/symbol label, not just color.
  local sev = vim.diagnostic.severity
  local s = icons.get().diag
  vim.diagnostic.config({
    underline = cfg.diagnostics.underline,
    severity_sort = true,
    update_in_insert = false,
    virtual_text = cfg.diagnostics.virtual_text and {
      spacing = 2,
      source = "if_many",
      prefix = function(d)
        return ({ [sev.ERROR] = s.error, [sev.WARN] = s.warn, [sev.INFO] = s.info, [sev.HINT] = s.hint })[d.severity]
      end,
    } or false,
    signs = cfg.diagnostics.signs and {
      text = { [sev.ERROR] = s.error, [sev.WARN] = s.warn, [sev.INFO] = s.info, [sev.HINT] = s.hint },
    } or false,
    float = { border = icons.border_name(), source = true, header = "" },
  })
end

return M
