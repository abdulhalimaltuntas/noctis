-- snacks.nvim: picker (dosya/metin/buffer/LSP arama), gezgin, input,
-- bildirimler, girinti rehberi, odak modu ve isteğe bağlı lazygit.
-- Dashboard, bigfile ve statusline NOCTIS'in kendi modülleridir.
local function ascii_icons()
  return {
    files = { enabled = false },
    tree = { vertical = "| ", middle = "|-", last = "`-" },
    ui = { live = "~", hidden = "h", ignored = "i", follow = "f", selected = "* ", unselected = "  " },
    git = { enabled = true, commit = "", staged = "S", added = "A", deleted = "D", ignored = "!", modified = "M", renamed = "R", unmerged = "U", untracked = "?" },
    diagnostics = { Error = "E ", Warn = "W ", Hint = "H ", Info = "I " },
    lsp = { unavailable = "-", enabled = "+", disabled = "x", attached = "@" },
    undo = { saved = "s" },
    keymaps = { nowait = "!" },
  }
end

return {
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 900,
    opts = function()
      local cfg = require("noctis.config").options
      local icons = require("noctis.ui.icons")
      local border = icons.border_name():find(",") and "single" or icons.border_name()
      return {
        picker = {
          enabled = true,
          ui_select = true,
          prompt = icons.enabled() and " " or "> ",
          icons = not icons.enabled() and ascii_icons() or nil,
          layout = {
            cycle = true,
            preset = function()
              return vim.o.columns >= 120 and "default" or "vertical"
            end,
          },
          matcher = { frecency = true, cwd_bonus = true },
          formatters = { file = { filename_first = true, truncate = "left" } },
          win = {
            input = {
              keys = {
                -- Picker içinde Esc doğrudan kapatır
                ["<Esc>"] = { "close", mode = { "n", "i" } },
              },
            },
          },
          sources = {
            explorer = {
              hidden = false,
              ignored = false,
              layout = { preset = "sidebar", preview = false, layout = { width = cfg.ui.explorer_width } },
              actions = {
                explorer_del = function(picker)
                  require("noctis.explorer").delete_action(picker)
                end,
              },
              win = {
                list = {
                  wo = { winhighlight = "Normal:NoctisExplorer,NormalNC:NoctisExplorer,CursorLine:SnacksPickerListCursorLine,FloatBorder:NoctisExplorerBorder,WinSeparator:NoctisExplorerBorder" },
                },
                input = {
                  wo = { winhighlight = "Normal:NoctisExplorer,NormalNC:NoctisExplorer,FloatBorder:NoctisExplorerBorder" },
                },
              },
            },
          },
        },
        explorer = { enabled = true, replace_netrw = true, trash = false },
        input = { enabled = true },
        notifier = {
          enabled = true,
          timeout = 3500,
          style = "compact",
          top_down = false,
          margin = { top = 1, right = 1, bottom = 1 },
          icons = not icons.enabled() and { error = "E ", warn = "W ", info = "I ", debug = "D ", trace = "T " } or nil,
        },
        indent = {
          enabled = cfg.ui.indent_guides,
          animate = { enabled = false },
          indent = { char = icons.enabled() and "│" or "|", hl = "SnacksIndent" },
          scope = { enabled = true, char = icons.enabled() and "│" or "|", hl = "SnacksIndentScope", underline = false },
          filter = function(buf)
            return vim.bo[buf].buftype == "" and not vim.b[buf].noctis_bigfile and vim.g.snacks_indent ~= false
          end,
        },
        zen = {
          toggles = { dim = false, git_signs = false, mini_diff_signs = false, diagnostics = true, inlay_hints = false },
          win = { backdrop = { transparent = false, blend = 0 }, width = 110 },
        },
        lazygit = { configure = true },
        styles = {
          input = { border = border, relative = "editor", row = 4 },
          notification = { border = border, wo = { wrap = true } },
          notification_history = { border = border },
          lazygit = { border = border },
        },
        -- NOCTIS kendi modüllerini kullanır:
        dashboard = { enabled = false },
        bigfile = { enabled = false },
        statuscolumn = { enabled = false },
        quickfile = { enabled = false },
        scroll = { enabled = false },
        words = { enabled = false },
      }
    end,
  },
}
