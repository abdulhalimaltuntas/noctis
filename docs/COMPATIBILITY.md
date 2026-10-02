# Verification and compatibility

This document separates what was **actually verified by running it** from what
wasn't. "Tested" is used only for things verified by the automated tests in this
repository or by observation in a real PTY session.

Verification environment: Linux 6.18 (x86_64, Ubuntu 24.04-based cloud VM),
Neovim 0.12.4, git 2.43, ripgrep 14.1, tmux 3.4, Python 3.11, Node 22.
Date: 2026-10-02.

## Platforms

| Platform | Status | Notes |
| --- | --- | --- |
| Linux x86_64 | ✅ Tested | All automated tests + real-PTY visual verification |
| Linux arm64 | ⚪ Not tested | No platform-specific code; expected to work |
| macOS | ⚪ Not tested | Uses POSIX tools (`cp -a`, `git`, `rg`). File watching is written per directory with `fs_event`; not verified on macOS. The `/proc`-based inotify check is skipped on macOS |
| Windows + WSL 2 | ⚪ Not tested | The Linux path is expected to work. On Windows file systems such as `/mnt/c`, inotify events are unreliable; the reconcile scan takes over |
| Windows (native) | ❌ Not supported | The launcher is bash; not a goal for the first release |

## Neovim and plugins

| Component | Verified version |
| --- | --- |
| Neovim | 0.12.4 (minimum 0.12.0; older versions are rejected by the launcher — tested) |
| Plugins | The commits in `app/lazy-lock.json` ([THIRD_PARTY.md](../THIRD_PARTY.md)) |

## AI tools

| Tool | Version | Status |
| --- | --- | --- |
| Claude Code | 2.1.287 | ✅ Launch/first-run screen, colors, resizing and keeping insert mode observed in a PTY (`claude-code*.png`). No prompt was sent; login and the file-writing flow were not verified in this environment |
| Codex CLI | — | ⚪ Not installed; not verified. Flags verified from the official source |
| Kimi Code | — | ⚪ Not installed; not verified. Flags verified from the official docs |
| Test CLI | 1.0 | ✅ End to end (kinds of file writes, Ctrl-C/SIGINT, exit code, keeps running while hidden) |

## Language servers

| Language | Verified | Status |
| --- | --- | --- |
| Python | pyright, ruff | ✅ Diagnostics, completion, go to definition and rename with the real server; formatting and format-on-save with ruff |
| Python Tree-sitter | parser v0.25.0 (built with tree-sitter CLI 0.27.0) | ✅ Tree-sitter highlighting with a parser, Vim syntax without one. Note: in this environment nvim-treesitter's tarball download got a 403 because of the network policy; the parser was fetched with git and built |
| JS/TS, HTML/CSS, JSON, Lua, Bash | — | ⚪ The packs are defined, but the servers weren't installed in this environment; not verified with a real server |

## Acceptance criteria

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Installs and opens in a clean temporary XDG; the existing Neovim setup is unaffected | ✅ | `tests/install_test.sh`; all Lua tests run with a temporary XDG |
| 2 | A project opens; a file is found, edited, saved, and correct when reopened | ✅ | `test_plugins` (find + open with the picker), `test_core` (save + reopen) |
| 3 | Paths with spaces/Turkish characters, `ğüşiİöç`, CRLF are preserved | ✅ | `test_core`, `test_ai` (project path `project ğüşiİöç`), `launcher_test` |
| 4 | Unsaved buffers are protected on close/quit; cancel works | ✅ | `test_core` |
| 5 | A file changed externally is never silently overwritten | ✅ | `test_core`, `test_ai` |
| 6 | Search jumps to the right file/line; bulk replace previews first | ✅ | `test_plugins` (grep → line 3), `test_core` (preview, exclusion, CRLF, regex) |
| 7 | Completion, diagnostics, go to definition and rename in at least one language | ✅ | `test_lsp` (pyright) |
| 8 | The terminal works; hide/show keeps the process and output; back to the editor | ✅ | `test_core`; `Ctrl-\ e` in a real PTY (`claude-code-exit.png`) |
| 9 | Git signs match the real diff; a folder without Git is fine | ✅ | `test_plugins` (gitsigns ↔ `git diff --numstat`) |
| 10 | Small/large size, resizing, long names, no icons | ✅ | `test_plugins` (no overflow at 60–200 columns, long name), `small-terminal.png`, `no-icons-ascii.png`, `claude-code-resized.png` |
| 11 | No network, missing `rg`/language server, `--safe` | ✅ | `test_safe` (two modes), `launcher_test` |
| 12 | Reinstall keeps settings; uninstall stays within bounds | ✅ | `tests/install_test.sh` |
| 13 | AI profiles in separate PTYs, the right root; hide/switch/resize/focus | ✅ | `test_ai` (PTY + fake CLI), `test_plugins` (focus), real Claude Code (`claude-code*.png`) |
| 14 | Pre-baseline staged/unstaged/untracked kept; Git ↔ interval separate; index unchanged | ✅ | `test_ai` (index bytes compared) |
| 15 | Normal writes, atomic saves, create/delete, subfolders; clean buffers update; project without Git | ✅ | `test_ai` |
| 16 | Unsaved edit + AI change: both contents kept | ✅ | `test_ai` (conflict, 3-way merge), `test_core` (deleted file) |
| 17 | Selective revert affects only its target; refused after a post-review change; index kept | ✅ | `test_ai` |
| 18 | No source attribution across several CLIs; "running" ≠ "done" | ✅ | `test_ai` (two-session warning, unattributed changes, evidence-based status) |
| 19 | A missing executable or a failed exit doesn't break the editor; no AI starts at launch | ✅ / ⚪ | `test_ai`, `test_core`. A missing account and network outages with real tools were **not verified** in this environment (the tool shows these in its own UI; NOCTIS reports the process exit) |
| 20 | Scope limits, exclusions, large/binary files are shown clearly; no revert is promised without known content | ✅ | `test_ai` |

Additional: the typing animation is covered by `test_core` (glow and fade,
text integrity, pastes/macros/big files skipped, toggle, 256-color fallback) and
was verified in a real PTY (the timer-driven redraw happens without a keypress).

Totals: **127 automated tests** — launcher 23, install 16, core 29, AI 22,
safe mode 7 + 7, plugins 14, LSP 9 (`tests/run.sh --plugins`).

## Visual verification

Screenshots are captured with `tests/visual/capture.sh` while NOCTIS runs in a
real PTY (tmux), then converted to PNG through HTML. A capture is the terminal's
cell content and colors at that moment. The demo project is generated by
`tests/visual/make-demo.sh`. The HTML renderer pins every non-Latin glyph to the
terminal cell grid (like a real terminal) so fallback-font glyphs can't shift a
line. Limitation: the font in the images (DejaVu Sans Mono + Nerd Font symbols)
and the cell spacing may differ from your terminal; the images aren't a screen
recording of a real terminal emulator.

Bugs found during visual review and fixed (see the commit history): the
Workbench top bar being cut off from the left, terminal mode being lost on resize
(Ctrl-C not reaching the tool), temporary diff buffers showing in the tab bar,
explorer blank rows drawn with a different background, command palette ranking,
and lines with Nerd Font icons shifting right in the screenshots.

## Not verified / known limits

- Not run on macOS, WSL or arm64.
- Codex CLI and Kimi Code were not tried in a real session.
- A real AI tool's file-writing flow (with an account) wasn't tried in this
  environment; the tracking logic was verified tool-independently with the test CLI.
- The JS/TS, HTML/CSS, JSON, Lua and Bash language servers weren't tried with a real server.
- The lazygit integration (optional) wasn't tried because lazygit wasn't
  installed; the fallback Git summary was tested.
- There was no system clipboard provider in this environment; `noctis --doctor`
  detected that correctly. Copying with xclip/wl-clipboard wasn't verified.
