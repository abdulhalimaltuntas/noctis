-- Command line in a popup at the top center (noice.nvim + nui.nvim), the way
-- LazyVim does it: `:` opens a titled popup with syntax-highlighted input and
-- the completion menu right under it; `/` and `?` searches stay at the bottom.
-- Only the command line and its completion menu are taken over: messages,
-- notifications (snacks) and LSP windows (blink) keep their own UI.
-- `ui.cmdline = "classic"` keeps Neovim's command line.
return {
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    cond = function()
      return require("noctis.config").options.ui.cmdline == "popup"
    end,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = function()
      local icons = require("noctis.ui.icons")
      local on = icons.enabled()
      local border = icons.border_opt()
      local function fmt(spec, nerd, plain)
        spec.icon = on and nerd or plain
        return spec
      end
      return {
        cmdline = {
          enabled = true,
          view = "cmdline_popup",
          format = {
            cmdline = fmt({ pattern = "^:", lang = "vim", title = " Command " }, "", ":"),
            search_down = fmt({ kind = "search", pattern = "^/", lang = "regex" }, " ", "/"),
            search_up = fmt({ kind = "search", pattern = "^%?", lang = "regex" }, " ", "?"),
            filter = fmt({ pattern = "^:%s*!", lang = "bash", title = " Shell " }, "$", "$"),
            lua = fmt({ pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" }, lang = "lua", title = " Lua " }, "", "lua"),
            help = fmt({ pattern = "^:%s*he?l?p?%s+", title = " Help " }, "󰋖", "?"),
            calculator = fmt({ pattern = "^=", lang = "vimnormal", title = " Calculator " }, "", "="),
            input = fmt({ view = "cmdline_input" }, "󰥻 ", ">"),
          },
        },
        -- Messages stay in Neovim's message area; vim.notify stays with snacks.
        messages = { enabled = false },
        notify = { enabled = false },
        popupmenu = { enabled = true, backend = "nui", kind_icons = on and {} or false },
        lsp = {
          progress = { enabled = false },
          hover = { enabled = false },
          signature = { enabled = false },
          message = { enabled = false },
        },
        presets = {
          bottom_search = true, -- / and ? keep the classic bottom line
          command_palette = true, -- popup at the top center, completion menu under it
          long_message_to_split = false,
          lsp_doc_border = false,
        },
        views = {
          cmdline_popup = {
            border = { style = border, padding = { 0, 1 } },
          },
          cmdline_popupmenu = {
            border = { style = border, padding = { 0, 1 } },
            -- The preset draws the menu on the editor background; keep it a popup surface
            win_options = {
              winhighlight = {
                Normal = "NoicePopupmenu",
                FloatBorder = "NoiceCmdlinePopupBorder",
                CursorLine = "NoicePopupmenuSelected",
                PmenuMatch = "NoicePopupmenuMatch",
              },
            },
          },
          cmdline_input = {
            border = { style = border, padding = { 0, 1 } },
          },
        },
      }
    end,
  },
  { "MunifTanjim/nui.nvim", lazy = true },
}
