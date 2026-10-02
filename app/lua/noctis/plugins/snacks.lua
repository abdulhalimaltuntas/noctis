-- snacks.nvim: picker (file/text/buffer/LSP search), explorer, input,
-- notifications, indent guides, focus mode and optional lazygit.
-- The dashboard, bigfile and statusline are NOCTIS's own modules.
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
      local border = icons.border_opt()
      return {
        picker = {
          enabled = true,
          ui_select = true,
          prompt = icons.enabled() and " " or "> ",
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
                -- Esc closes the picker directly
                ["<Esc>"] = { "close", mode = { "n", "i" } },
              },
            },
          },
          sources = {
            explorer = {
              title = "Files",
              hidden = false,
              ignored = false,
              layout = { preset = "sidebar", preview = false, layout = { width = cfg.ui.explorer_width } },
              -- A/M/D marks for files changed in the AI review interval
              format = function(item, picker)
                local ret = require("snacks.picker.format").file(item, picker)
                if not item.dir and package.loaded["noctis.ai.tracker"] then
                  local mark = require("noctis.ai").explorer_mark(item.file)
                  if mark then
                    ret[#ret + 1] = { " " .. mark.text, mark.hl }
                  end
                end
                return ret
              end,
              actions = {
                explorer_del = function(picker)
                  require("noctis.explorer").delete_action(picker)
                end,
              },
              win = {
                list = {
                  wo = {
                    winhighlight = "Normal:NoctisExplorer,NormalNC:NoctisExplorer,NormalFloat:NoctisExplorer,EndOfBuffer:NoctisExplorer,CursorLine:SnacksPickerListCursorLine,FloatBorder:NoctisExplorerBorder,WinSeparator:NoctisExplorerBorder",
                  },
                },
                input = {
                  wo = { winhighlight = "Normal:NoctisExplorer,NormalNC:NoctisExplorer,NormalFloat:NoctisExplorer,FloatBorder:NoctisExplorerBorder" },
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
        -- NOCTIS uses its own modules:
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
