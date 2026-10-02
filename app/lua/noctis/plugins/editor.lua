-- Key hints (which-key), Git signs (gitsigns), icons (mini.icons).
return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = function()
      local icons = require("noctis.ui.icons")
      local groups = {}
      for _, g in ipairs(require("noctis.registry").groups) do
        groups[#groups + 1] = { g[1], group = g[2] }
      end
      groups[#groups + 1] = { "[", group = "previous" }
      groups[#groups + 1] = { "]", group = "next" }
      groups[#groups + 1] = { "g", group = "git / LSP / motion" }
      return {
        preset = "modern",
        delay = function(ctx)
          return ctx.plugin and 0 or 350
        end,
        spec = groups,
        icons = {
          mappings = icons.enabled(),
          breadcrumb = icons.enabled() and "»" or ">",
          separator = icons.enabled() and "➜" or "->",
          group = icons.enabled() and "+" or "+",
        },
        win = { border = icons.border_opt(), title = true },
        -- which-key doesn't trigger in terminal mode: shell/AI keys are preserved
        triggers = { { "<auto>", mode = "nxso" } },
      }
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = function()
      local plain = not require("noctis.ui.icons").enabled()
      local bar = plain and "|" or "▎"
      return {
        signs = {
          add = { text = bar },
          change = { text = bar },
          delete = { text = plain and "_" or "▁" },
          topdelete = { text = plain and "-" or "▔" },
          changedelete = { text = plain and "~" or "▎" },
          untracked = { text = plain and ":" or "┆" },
        },
        signs_staged_enable = false,
        attach_to_untracked = true,
        preview_config = { border = require("noctis.ui.icons").border() },
        on_attach = function(buf)
          local gs = require("gitsigns")
          vim.keymap.set("n", "]h", function()
            gs.nav_hunk("next")
          end, { buffer = buf, desc = "Next Git hunk" })
          vim.keymap.set("n", "[h", function()
            gs.nav_hunk("prev")
          end, { buffer = buf, desc = "Previous Git hunk" })
        end,
      }
    end,
  },
  {
    "nvim-mini/mini.icons",
    lazy = true, -- installed regardless of the terminal; loaded only when icons are on
    opts = {},
    init = function()
      if not require("noctis.ui.icons").enabled() then
        return
      end
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
}
