# Performance

## Startup time

The measured value is the **"first screen update"** moment from Neovim's
`--startuptime` output: the time from process start until the first screen is
drawn (ms). It's measured inside a real TUI (tmux, 120×35, `TERM=tmux-256color`).

- **Cold**: OS page cache dropped (`drop_caches`, as root) and the Lua bytecode /
  lazy.nvim cache empty. Median of 3 runs.
- **Warm**: caches populated; median and range of 1 warm-up + 10 consecutive runs.
- Plugin install time (`noctis --setup`) is **not** part of this measurement.
- Since Neovim 0.10 the TUI client and the embedded server write separate blocks
  to the same file; the script reads the value from the server block.

Command: `DATA=<XDG_DATA_HOME with plugins> tests/perf.sh 10`

### Results (2026-10-02)

Machine: Intel Xeon @ 2.10 GHz, 4 cores, 15 GiB RAM (cloud VM), Linux 6.18,
Neovim 0.12.4, 10 plugins installed, typing animation on (default).

| Scenario | Cold (median) | Warm (median) | Warm range |
| --- | --- | --- | --- |
| Dashboard (no arguments) | 70.0 ms | 40.8 ms | 37.7–46.6 ms |
| Python file (`main.py`) | 112.6 ms | 57.1 ms | 53.9–66.6 ms |
| Safe mode (`--safe`) | 40.6 ms | 28.8 ms | 27.8–30.2 ms |

Well under the ~300 ms first-screen target. When opening a Python file,
lspconfig and gitsigns load on `BufReadPre`; the language server (pyright)
starts and runs its first analysis **after** the first screen, in the background
(pyright's cold analysis took anywhere from a few seconds to 15+ seconds on
this machine).

Results vary on other hardware; measure on your own machine with the same script.

## Change tracking latency

`tests/lua/test_ai.lua` measures the time from an external process (the test
CLI) finishing a file write to the change showing up in the list: **~370 ms**
(250 ms debounce + 120 ms write-settle check + diff). The target is ~1 s. Recording
the baseline of a small project (9 files) took ~25 ms; the baseline is recorded
in ~12 ms chunks without blocking the UI.

The reconcile scan (for missed events) adapts to the project: it runs every
`reconcile_ms` (4 s) on small projects and backs off to at most once every 60 s
when a scan is slow, so large repositories don't keep a CPU busy.

## Typing animation

One `InsertCharPre` autocmd per keystroke and a single shared 40 ms timer that
only runs while a glow is visible (at most 48 extmarks). Pastes, macros and big
files are skipped. Turn it off with `ui.typing_animation = false` or `Space u a`.

## Big files

The default threshold is 2 MiB or 50,000 lines (the `bigfile` setting). For a
file over the threshold, syntax, Tree-sitter, LSP, folding and visible
whitespace/cursorline are turned off; the file stays editable, swap and undo are
kept, and the statusline shows a **BIG FILE** label.
