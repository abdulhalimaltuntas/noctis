# Changelog

All notable changes to NOCTIS are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/abdulhalimaltuntas/noctis/releases/tag/v0.1.0
