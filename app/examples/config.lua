-- NOCTIS user settings
-- Location: ~/.config/noctis/config.lua  (respects XDG_CONFIG_HOME)
-- Updates never touch this file. Changes apply after NOCTIS restarts.
-- Invalid values are reported with an explanation at startup and replaced by
-- the default. Every field is optional.
return {
  -- Theme: "midnight-violet" | "glacier" | "amber"  (also Space u t)
  -- theme = "midnight-violet",

  -- Let the terminal provide the editor background (transparency is a terminal feature)
  -- transparent = false,

  -- Nerd Font icons. Set to false without such a font; the interface still works fully.
  -- icons = true,

  -- Borders: "rounded" | "single" | "ascii"
  -- borders = "rounded",

  -- Color: "auto" (query the terminal) | true (24-bit) | false (256-color fallback)
  -- truecolor = "auto",

  -- First-launch tour
  -- welcome = true,

  ui = {
    -- relative_numbers = false,
    -- indent_guides = true,
    -- cursorline = true,
    -- explorer_width = 30, -- 16..80
    -- wrap = false,
    -- typing_animation = true, -- typed characters glow briefly (Space u a)
  },

  diagnostics = {
    -- virtual_text = true,
    -- signs = true,
    -- underline = true,
  },

  -- Format on save (off by default). Only for specific filetypes:
  format_on_save = {
    -- enabled = true,
    -- filetypes = { "python", "lua" }, -- empty = all filetypes
    -- timeout_ms = 1500,
  },

  -- Enabled language packs. Components are never downloaded on their own (:NoctisLang)
  -- languages = { "python", "javascript", "html", "json", "lua", "bash" },

  -- Big file mode threshold
  -- bigfile = { size = 2 * 1024 * 1024, lines = 50000 },

  -- Clipboard: "auto" | "system" | "internal"
  -- clipboard = "auto",

  -- Save the project layout on quit (restoring is always an explicit command: Space q r)
  -- session = { autosave = true },

  -- Change/disable keys: command id → key or false.
  -- Ids: :NoctisKeys  or docs/KEYMAPS.md
  keymaps = {
    -- ["files.grep"] = "<leader>/",
    -- ["ui.focus"] = false,
  },

  -- Tasks (Space t r). Commands are argument lists; a string instead of a list
  -- runs in the shell. None of them ever start on their own.
  tasks = {
    -- { name = "Tests", cmd = { "pytest", "-q" } },
    -- { name = "Server", cmd = { "npm", "run", "dev" } },
  },

  ai = {
    -- Profiles: extend the built-ins (claude, codex, kimi, opencode) or add your own.
    -- cmd is always an argument list; it's never joined into shell text.
    profiles = {
      -- claude = { cmd = { "/opt/claude/bin/claude" } },          -- different location
      -- codex = false,                                            -- remove from the list
      -- aider = { label = "Aider", cmd = { "aider", "--no-auto-commits" } },
      -- custom = { label = "My tool", cmd = { "my-tool" }, env = { MY_MODE = "1" } },
    },
    -- layout = "auto", -- "auto" | "right" | "bottom" | "full"
    -- width = 0.42,    -- right panel ratio
    -- height = 0.40,   -- bottom panel ratio
    baseline = {
      -- max_files = 5000,
      -- max_file_size = 1024 * 1024,
      -- max_total_size = 64 * 1024 * 1024,
      -- exclude = { "*.sqlite", "data/**" },
      -- respect_gitignore = true,
    },
    watch = {
      -- debounce_ms = 250,
      -- reconcile_ms = 4000, -- shortest interval; grows automatically on slow scans (≤60 s)
      -- max_dirs = 4000,
    },
    -- retention_days = 14,
    -- max_store_mb = 512,
  },
}
