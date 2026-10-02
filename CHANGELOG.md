# Changelog

All notable changes to NOCTIS are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Interface

- **Command line in a popup at the top center**, with the completion menu right
  under it (noice.nvim + nui.nvim, as in LazyVim). Command, shell, Lua, help and
  calculator lines each get their own icon, title and edge color; `/` and `?`
  stay on the bottom line. Messages, notifications and LSP windows keep their
  current UI. `ui.cmdline = "classic"` turns it off.
- Command line completion lists names only (no kind/source columns).
- Pending keys (`d2`, `"a`, …) show in the statusline instead of the bottom-right
  corner of the message line.
- **Daybreak**, a light theme. `:set background=light` switches to it and `dark`
  returns to the last dark theme; light terminals get a readable ANSI palette.
- Command palette puts recently used commands first (frecency, two-week
  half-life); palette rows and dashboard actions carry a glyph per command
  group; recent files show their file type icon.
- The Changes view explains the review flow before the first AI session, with
  live keys.

### Fixes

- Comments were below WCAG AA (3.7–4.4:1) in all three themes; they now pass on
  every surface. Secondary text and matches on selected menu rows (3.6:1) and
  popup borders (1.3:1) were also too faint.
- Code punctuation and operators have their own tones instead of the UI's
  chrome grey. Transparent mode tints the cursor line from the accent.
- Fourteen Nerd Font icons were blank (diagnostics, Git branch, lock, terminal,
  folder, search, warning, conflict, new file, palette, project…).
- "3 hunk" in the diff header; an untranslated string in the Git view.

### Quality

- `theme.audit()` checks every highlight group of every theme against WCAG
  floors (text 4.5:1, dimmed hints 3:1, borders 2:1); it runs in the tests and
  in `noctis --doctor`. A test also fails on any blank Nerd Font icon.

## [0.1.0] — 2026-10-02

First public release. Tested on Linux x86_64 with Neovim 0.12.4.

### AI Workbench

- Run **Claude Code, Codex CLI, Kimi Code and OpenCode** (or any CLI you define)
  in real terminal sessions pinned to the project root. Hiding the panel never
  stops a process; the tool's own keys (including `Esc` and `Ctrl-C`) reach it.
- Before a tool starts, the project's **on-disk content** and Git state are
  recorded as a baseline, read-only (the Git index is never touched).
- Every later file change is **tracked live** (~370 ms from write to list):
  normal writes, atomic saves, create/delete, new subfolders, `.gitignore` respected.
- Review as a **side-by-side or unified diff**, mark files as reviewed, and
  **revert per hunk or per file** — refused if the file changed again after your
  review or has unsaved edits; the previous content is backed up first.
- Status is shown **only by evidence** (starting / running / exited / failed);
  changes are never attributed to a tool by assumption.
- When a tool exits, its last output stays on screen (Terminal mode is left so a
  stray key can't close it).

### Editor

- Command palette, keymaps, which-key help and `docs/KEYMAPS.md` generated from a
  single command registry, with conflict checks.
- **Midnight Violet**, **Glacier** and **Amber** themes from one set of design
  tokens; 256-color fallback; fully usable without a Nerd Font.
- **Typing animation**: typed characters glow briefly and fade (`Space u a` to toggle).
- Dashboard with real recent files/projects, a skippable one-minute tour,
  file explorer, fuzzy finding, project search and **search & replace with preview**.
- Language packs for Python, JS/TS, HTML/CSS, JSON, Lua and Bash (servers,
  parsers and formatters installed only on request); format-on-save off by default.
- Terminal panel that keeps processes alive, task runner, Git signs and summary,
  sessions, big-file mode.

### Data safety

- Unsaved edits are never overwritten by an external change; a **3-way merge**
  is offered. Deleted or moved files keep their buffer content.
- Recoverable deletes (NOCTIS trash), persistent undo and swap; CRLF and UTF-8 preserved.

### Installation and quality

- User-space installer and uninstaller; settings are kept across reinstalls.
- **No network on startup**: plugins are pinned in `app/lazy-lock.json` and
  downloaded only by `noctis --setup`.
- `noctis --doctor`, `noctis --safe`, `:checkhealth noctis`.
- First screen in ~41 ms warm / ~70 ms cold (see `docs/PERFORMANCE.md`).
- 128 automated tests; screenshots captured from a real PTY.

### Known limits

- macOS, WSL and arm64 are not tested yet.
- Codex CLI and Kimi Code were not tried in a real session; Claude Code and
  OpenCode were verified in a PTY without sending prompts.
- AI changes are reviewed after they're written; there's no pre-write approval yet.

[Unreleased]: https://github.com/abdulhalimaltuntas/noctis/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/abdulhalimaltuntas/noctis/releases/tag/v0.1.0
