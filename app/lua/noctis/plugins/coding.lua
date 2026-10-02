-- Completion (blink.cmp), LSP configs (nvim-lspconfig), Tree-sitter,
-- formatter management (conform), tool installation (mason).
return {
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    opts = function()
      local icons = require("noctis.ui.icons")
      local border = icons.border_opt()
      return {
        -- The menu never changes code on its own: no item is preselected
        -- and selecting doesn't insert text automatically. Enter accepts only
        -- when an item was explicitly selected; otherwise it's a new line.
        keymap = {
          preset = "enter",
          ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
          ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        },
        completion = {
          list = { selection = { preselect = false, auto_insert = false } },
          menu = {
            border = border,
            draw = {
              -- Why an item is shown stays visible: kind (Function, Variable…) and source (LSP, Buffer…)
              columns = icons.enabled()
                  and { { "label", "label_description", gap = 1 }, { "kind_icon", "kind", gap = 1 }, { "source_name" } }
                or { { "label", "label_description", gap = 1 }, { "kind" }, { "source_name" } },
            },
          },
          documentation = { auto_show = true, auto_show_delay_ms = 300, window = { border = border } },
          ghost_text = { enabled = false },
          accept = { auto_brackets = { enabled = true } },
        },
        signature = { enabled = true, window = { border = border } },
        appearance = { nerd_font_variant = "mono", use_nvim_cmp_as_default = false },
        sources = {
          default = { "lsp", "path", "snippets", "buffer" },
          providers = {
            snippets = { opts = { search_paths = { vim.fn.stdpath("config") .. "/snippets" }, friendly_snippets = false } },
          },
        },
        -- Lua matcher that works without downloading the Rust binary (offline-safe)
        fuzzy = { implementation = "lua" },
        enabled = function()
          return vim.bo.buftype ~= "prompt" and vim.b.completion ~= false
        end,
      }
    end,
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("noctis.lang").setup_lsp()
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false, -- the plugin doesn't support lazy loading; it only contains queries and an installer
    config = function()
      require("nvim-treesitter").setup({})
      require("noctis.lang").setup_treesitter()
    end,
  },
  {
    "stevearc/conform.nvim",
    cmd = { "ConformInfo" },
    event = { "BufWritePre" },
    opts = function()
      local cfg = require("noctis.config").options.format_on_save
      return {
        formatters_by_ft = require("noctis.lang").formatters_by_ft(),
        default_format_opts = { lsp_format = "fallback", timeout_ms = cfg.timeout_ms },
        format_on_save = function(buf)
          return require("noctis.format").on_save_opts(buf)
        end,
        notify_on_error = true,
        notify_no_formatters = false,
      }
    end,
  },
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonLog" },
    opts = function()
      local icons = require("noctis.ui.icons")
      return {
        PATH = "skip", -- NOCTIS adds it to PATH (lang.setup_path), even before Mason loads
        ui = {
          border = icons.border_opt(),
          icons = icons.enabled() and nil or { package_installed = "+", package_pending = "~", package_uninstalled = "-" },
        },
      }
    end,
  },
}
