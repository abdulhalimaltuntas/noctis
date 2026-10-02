# Architecture

```
bin/noctis                  Launcher (bash): flags, NVIM_APPNAME, -u app/init.lua, exec
app/BRAND                   Product name / command / appname / version — single source of truth
app/init.lua                Entry point; startup error → log + visible error + --safe hint
app/lazy-lock.json          Plugin lockfile (under version control)
app/examples/config.lua     Annotated user settings example
app/colors/*.lua            :colorscheme entry points
app/lua/noctis/
  init.lua                  Orchestration (every subsystem is a separately guarded step)
  config.lua                Defaults + schema validation (config.lua lives with the user)
  options.lua · keymaps.lua · autocmds.lua · usercmds.lua
  registry.lua · commands.lua   Command registry: palette, keymaps, which-key, KEYMAPS.md
  palette.lua · pick.lua · explorer.lua · help.lua · onboarding.lua
  theme/{palettes,tokens,highlights,init}.lua   Design system
  ui/{statusline,tabline,dashboard,layout,float,bar,icons,typing}.lua
  sync.lua                  Buffer ↔ disk sync, conflicts, 3-way merge
  files.lua · trash.lua · buffers.lua · quit.lua · session.lua · project.lua
  terminal.lua · tasks.lua · replace.lua · git.lua · format.lua · lang.lua
  bigfile.lua · clipboard.lua · doctor.lua · health.lua · setup.lua · lazy.lua
  plugins/{snacks,editor,coding}.lua   lazy.nvim plugin specs
  ai/
    profiles.lua · sessions.lua · workbench.lua · init.lua   Process/session side
    store.lua · scope.lua · baseline.lua · watcher.lua · tracker.lua   Change detection
    hunks.lua · review.lua                                             Review/revert
scripts/install.sh · scripts/uninstall.sh
tools/noctis-fake-ai        Deterministic test CLI
tests/                      launcher, core, AI, safe mode, plugins, LSP, performance, visual
```

## Key decisions

**Neovim core, original Lua layer.** The text engine, the Vim interpreter, the
terminal emulator, undo, swap and diff come from Neovim. NOCTIS doesn't rewrite
them; it adds the experience, the data-safety rules and the AI Workbench. The
minimum is Neovim 0.12.0: `vim.text.diff`, `jobstart({term=true})`,
`vim.lsp.config/enable` and the `main` branch of nvim-treesitter require it.
The tested version is 0.12.4.

**Separate app and user directories.** The launcher uses `NVIM_APPNAME=noctis`
and `-u <app>/init.lua`. The app files (`~/.local/share/noctis/app`) are replaced
completely on update; the user settings (`~/.config/noctis/config.lua`) are a
separate file that is never touched. The user's regular Neovim setup is
unaffected; terminals inside NOCTIS restore the user's original `NVIM_APPNAME`.

**Explicit setup, no network on startup.** lazy.nvim is bootstrapped only during
`noctis --setup`; `install.missing`, update checks and change detection are off
on a normal launch. A missing plugin is reported with a single warning and the
editor runs in basic mode; there's no repeating download loop.

**Commands from a single source.** `commands.lua` defines every command with an
id, title, description, group, default key, availability check and action. The
palette, Normal mode mappings, which-key groups, `:Noctis <id>`, the help screen
and `docs/KEYMAPS.md` are generated from it. User overrides use the command id;
conflict/prefix checks run in the tests and in `:checkhealth`. An unavailable
command (missing plugin, `rg`, LSP) is shown with the reason.

**Design system.** Variants define only 11 base tokens + 8 syntax hues; derived
tones such as the selection, search, diff and diagnostics backgrounds are
produced with the same formulas in `tokens.lua`. Components use highlight groups,
never colors; when the theme changes, the statusline, tabline, explorer,
completion, Git, diagnostics and the Workbench all update together. Without
truecolor every color is mapped to the nearest xterm-256 color. WCAG contrasts
were measured (body text 14.9:1, comments ≥4.4:1).

**Typing animation (`ui/typing.lua`).** One `InsertCharPre` autocmd records each
typed character; after it's inserted, its position is verified and it gets an
extmark whose background steps from the accent color back to the line
background (6 steps, ~240 ms) on a single shared timer that only runs while a
glow is alive. Only the background is animated, so syntax colors are untouched.
Bursts (pastes), macros, big files, special buffers and 256-color terminals are
skipped.

**Data-safety layer (`sync.lua`).** Built on Neovim's `FileChangedShell`
mechanism: a safe reload for clean buffers (view kept, changed lines highlighted,
undoable via `undoreload`), never an automatic reload/save for dirty buffers.
For every buffer, the "last synced content" and the disk signature (mtime ns,
size, inode) are kept; the disk is checked again before saving. Merging uses
`git merge-file` (no Git repository needed). Deleting moves files to the NOCTIS
trash (independent of the system trash). Persistent undo and swap stay on.

**AI: process management and change detection are separate.** `sessions.lua`
only manages PTY processes. `tracker.lua` tracks file changes by any program
without assuming which program made them; it works without an AI session too.
The baseline is content-addressed (sha256), deduplicated and stored outside the
project. Watching is per directory (no `recursive` on Linux); events go through
a debounce + write-settle check, and missed ones are caught by a low-frequency
reconcile whose interval adapts to the scan cost. Reverts work on lines with
their terminators (`\n`/`\r\n`), so they're byte-exact, and they require the
disk content to match the reviewed version.

**Search and replace.** Preview and apply use the same engine (ripgrep
`--replace`), so Lua patterns and Rust regex can't diverge in meaning. While
applying, every line is verified to still be the previewed original. The output
is read without `vim.system`'s text normalization (CRLF is preserved).

## Plugin choice (one solution per capability)

| Capability | Choice | Rationale |
| --- | --- | --- |
| Plugin management | lazy.nvim | Lockfile, lazy loading, `restore`; the spec's default |
| Picker + explorer + notifications + input + focus mode + lazygit | snacks.nvim | Several capabilities in one dependency; no separate picker/explorer. Its dashboard, bigfile and statusline are off — those are NOCTIS's own modules |
| Key hints | which-key.nvim | Groups come from the registry; doesn't trigger in terminal mode |
| Completion | blink.cmp (Lua matcher) | No preselection or auto-insert; kind/source column. Doesn't download the Rust binary |
| LSP configs | nvim-lspconfig + `vim.lsp.enable` | Built-in LSP client; only servers whose executable is found are enabled |
| Syntax | nvim-treesitter (`main`) | Parsers are optional; Vim syntax otherwise |
| Git signs | gitsigns.nvim | Line signs, hunk preview/reset, blame |
| Formatting | conform.nvim | `stop_after_first`, LSP only as a fallback, timeouts |
| Tool installation | mason.nvim | Only when the user starts it; NOCTIS adds it to PATH |
| Icons | mini.icons | Loaded when icons are on; always installed (no network needed when the terminal changes) |

Not used: bufferline, lualine, noice, telescope, nvim-cmp, neo-tree — no second
solution doing the same job is loaded.

## Lazy loading

`snacks.nvim` and `nvim-treesitter` (the plugin doesn't support lazy loading)
load at startup; which-key on `VeryLazy`, blink.cmp on `InsertEnter`/`CmdlineEnter`,
lspconfig and gitsigns on `BufReadPre`, conform on `BufWritePre`/command, mason on
command. A not-yet-loaded feature called from the palette or a key is loaded by
lazy.nvim through `require` (verified in the tests).

## Deliberately not done

Telemetry, automatic updates, unsafe execution of project-local Lua/config (the
project task file is read only after `vim.secure` trust approval), starting an
AI tool on its own, storing terminal transcripts, storing API keys.
