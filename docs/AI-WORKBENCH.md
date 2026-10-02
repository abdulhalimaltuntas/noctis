# AI Workbench guide

The AI Workbench runs existing AI coding CLIs (Claude Code, Codex CLI, Kimi Code,
OpenCode or a tool you define) inside NOCTIS in **real terminal sessions**, watches the
changes these tools (or any other program) make to project files live, and lets
you review them and, if needed, revert them safely.

NOCTIS is not a new AI chat service or model API layer: it uses the tool's own
account, login flow, permissions and network behavior. NOCTIS stores no API
keys, doesn't change tool permissions, never sends source code or terminal
transcripts to an external service, and never starts an AI tool on its own.

![AI Workbench](screenshots/ai-workbench.png)

## Quick start

| Key | Action |
| --- | --- |
| `Space a n` | Pick a tool and start a new session (the baseline is recorded first) |
| `Space a a` | Show the panel → focus it → hide it (hiding doesn't stop the process) |
| `Space a s` | Switch between sessions and the "Changes" view |
| `Space a d` | Show the changes in the review interval |
| `Space a c` | Close the interval and take a new baseline (doesn't touch files) |
| `Space a f` | Focus the AI terminal |
| `Space a h` / `a U` / `a m` | For the file in the editor: revert hunk / revert file / mark reviewed |
| `Space a i` | Scope details (recorded / excluded files, limits) |
| `Space a x` / `a r` | Stop / restart the session (with confirmation) |
| `Space a R` | Resume the tool's previous session (only via its documented flag) |
| `Space a e` | Prepare the selection as context (shown first; Enter isn't sent) |
| `Ctrl-\ e` | Back from the AI terminal to the editor |

While the terminal has focus, every key goes to the tool, `Esc` and `Ctrl-C`
included (the tool's own behavior is kept). This was verified in a real PTY:
`Ctrl-C` reaches the tool as SIGINT, and the session status becomes
"exited (130)" based on evidence.

## Profiles

| Profile | Executable | Version query | Resume | Source |
| --- | --- | --- | --- | --- |
| Claude Code | `claude` | `claude --version` | `claude --continue` (latest conversation in the directory) | [CLI reference](https://code.claude.com/docs/en/cli-reference) |
| Codex CLI | `codex` | `codex --version` | `codex resume --last` | [openai/codex](https://github.com/openai/codex) (`codex-rs/cli`), [docs](https://developers.openai.com/codex/cli) |
| Kimi Code | `kimi` | `kimi --version` | `kimi --continue` (latest session in the directory) | [kimi command](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html), [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) |
| OpenCode | `opencode` | `opencode --version` | `opencode --continue` (latest session) | [CLI docs](https://opencode.ai/docs/cli/), `opencode --help` (v1.18.34) |
| Custom | the argument list you define | optional | — | `config.lua` |

The default launch uses **no flags** (the tool's normal interactive mode). The
flags above are used only because they were verified in each tool's official
documentation/source; no other flags are added. Note: the older Python-based
`kimi-cli` is archived; the profile targets its replacement, the Kimi Code CLI
(`kimi`).

The program and its arguments are passed as an argument list, never joined into
shell text. A custom profile example (`~/.config/noctis/config.lua`):

```lua
return {
  ai = {
    profiles = {
      claude = { cmd = { "/opt/claude/bin/claude" } },       -- different location
      aider = { label = "Aider", cmd = { "aider", "--no-auto-commits" } },
      codex = false,                                         -- remove from the list
    },
  },
}
```

If the tool isn't installed, no session is started; the panel shows the
executable it looked for, the official install command and a link to the docs.
The editor is unaffected.

## Project binding and sessions

- Every session has a **fixed project root**, a tool label, a unique id and a
  terminal buffer. Switching to another project doesn't change the running
  process's working directory; the panel's top bar shows the session's root.
- Several sessions can be open. Starting a second tool in the same working tree
  asks for confirmation because of the concurrent-write risk, and a warning
  shows in the panel. Recommended use: a single editing tool. NOCTIS can't lock
  other programs out of writing files.
- **Status is shown only by evidence**: *starting* (the process started, no
  output yet), *running* (the process is alive and produced output),
  *exited (code)*, *failed to start*. "Task finished", "waiting for approval",
  tokens/cost and the like are never guessed from terminal text or shown. A live
  process doesn't prove a task is in progress, and silence doesn't prove it's done.
- When a tool exits while you're typing in it, NOCTIS leaves Terminal mode, so a
  stray key can't close the terminal and wipe the tool's last output (Neovim
  deletes an exited terminal on the next key in Terminal mode). The output stays
  scrollable and copyable; the session shows *exited (code)*.
- When quitting with `Space q q`, running sessions are listed; the processes are
  stopped on quit (there's no promise of them staying in the background).
- Layout: a right panel on wide screens, a bottom panel at medium width, the full
  area on narrow screens (tabs with one view). The layout adapts when the window
  is resized; focus and terminal (insert) mode are kept.

## Review interval and baseline

Before the first AI session, a **review interval** is started for the project:

1. The **current disk content** of the in-scope text files is copied to a local,
   content-addressed store (not just hashes — so the previous content can be
   shown and reverted).
2. For a Git repository, the current commit, branch and staged/unstaged/untracked
   state are recorded **read-only** (`git --no-optional-locks`; not even an index
   refresh is written). The branch, index, stash and working tree are never
   changed — the tests verify this by comparing the index bytes.
3. The tool isn't started until the baseline is complete. The baseline is
   recorded in chunks without blocking the UI.

This way **user edits that existed before the baseline are never shown as new
AI changes**. The two comparisons are labeled separately:

- **Review interval** (default): changes detected since the baseline.
- **Git** (`g` key): the working tree vs HEAD (edits from before the baseline included).

The active interval belongs to the project and survives restarting NOCTIS
(changes made while it was closed are caught by a reconcile at startup).
Switching tools or projects never resets the interval behind your back; a new
interval starts only with `Space a c`.

### Scope and limits

| Rule | Default |
| --- | --- |
| `.gitignore` / `.ignore` | applied (even outside a Git repository) |
| Folders never watched | `.git`, `node_modules`, `.venv`, `venv`, `__pycache__`, `dist`, `build`, `target`, `coverage`, cache folders… |
| Sensitive files | `.env*`, `*.pem`, `*.key`, `id_rsa*`, `.npmrc`, `.netrc`, `credentials`, `secrets.*` … their content is **never copied** |
| Size per file | 1 MiB (`ai.baseline.max_file_size`) |
| Total content | 64 MiB (`ai.baseline.max_total_size`) |
| Files with recorded content | 5000 (`ai.baseline.max_files`) |
| Symbolic links | not followed; paths leading outside the project are neither watched nor reverted |
| Retention | 14 days, at most 512 MB (`ai.retention_days`, `ai.max_store_mb`) |
| Location | `~/.local/state/noctis/noctis/ai/<project-key>/` (outside the project, 0700) |

If an out-of-scope file changes, it shows up in the list, but it says clearly that
**there is no previous content**, and no revert is offered. `Space a i` lists
which files were excluded and why.

## Live tracking

- File creation, modification, deletion, atomic saves (temp file + rename) and
  new subfolders are tracked. libuv's `recursive` flag isn't supported on Linux
  (verified), so **every directory is watched separately** and new directories
  are added as events arrive. If the watch limit is exceeded, the rest is tracked
  by a periodic reconcile, and the panel says so.
- Events are coalesced; the diff is computed after a short write-settle check.
  Measured latency from the end of a write to showing up in the list: **~370 ms**
  (test: `tests/lua/test_ai.lua`).
- For missed events, a reconcile runs when focus returns and at a low frequency;
  the project isn't scanned on every keystroke. The interval adapts to how long
  the last scan took: `reconcile_ms` (default 4 s) on small projects, at most once
  every 60 s on large projects with slow scans.
- Notifications are batched (at most one message every few seconds); you're
  never forced into a new file. Files you saved yourself don't trigger a
  notification (they still appear in the list).
- In the explorer, files changed in the interval are marked **A / M / D**.

**Attribution:** a file system event doesn't say which program made a change.
So changes are never attributed to a specific tool; the label is always
"change detected in the review interval". If you or another tool write at the
same time, those changes also land in the interval.

### Open buffer behavior

1. **Clean buffer**: the settled disk content is reloaded; the cursor and scroll
   position are kept, and changed lines are highlighted briefly and subtly. The
   reload can be undone with `u`.
2. **Unsaved edits**: no automatic reload or save. The buffer is marked
   **CONFLICT**; on save the disk is checked again.
3. **On conflict** (`:NoctisConflict` or at save time): compare, 3-way merge
   (base: the content the buffer was last in sync with — not necessarily the AI
   baseline), write the local version (the overwritten disk content is backed
   up), load the disk version (a local copy is kept first), or copy the local
   content to a separate file. Without a reliable base, a manual diff and the
   separate-copy path are offered.
4. **File deleted/moved**: the buffer content is never lost (it counts as
   modified and you're asked on quit); you can save to the same path or a new
   location.

A suggestion shown in the AI terminal but never written to disk is not a file
change; nothing is marked unless the file state changes.

## Review and revert

In the change list: `Enter` diff, `r` reviewed, `u` revert file, `o` open,
`g` Git view, `R` refresh, `q` hide.

- A **side-by-side** diff opens on wide screens (≥140 columns), a **unified** diff
  on narrow ones. Add/delete/change colors are fixed; +/− line counts are shown
  per file. Binary files show size information instead of a text diff.
- The **reviewed** mark is invalidated automatically if the content changes
  again. In this version the tool writes straight to the working tree, so review
  happens **afterwards**; "reviewed" is not a pre-write approval.
- **Revert** (`X` hunk, `U`/`u` file, `Space a h` / `Space a U` in the editor):
  - The disk content must still match the version you reviewed; if another
    write happened in between, the operation is refused and you're asked to
    review the diff again.
  - It's refused if the file's open buffer has unsaved edits.
  - Only the chosen hunk/file changes; other changes, earlier user edits and the
    Git index are kept. `git reset`, `git clean` or project-wide rollbacks are
    never used.
  - The content before the revert is copied to
    `~/.local/state/noctis/noctis/recovered/`; reverting an added file moves it
    to the NOCTIS trash (restore it with `Space f T`).
  - Without previous content (out of scope), that's said clearly and nothing is done.
- A **new interval** (`Space a c`) doesn't change files; the old record is kept
  for the retention period.

## Sending context

`Space a e` (Normal or Visual mode) prepares the selected code as a `path:line`
header plus a code block and **shows it in a preview first**; if you confirm, it's
added to the tool's input line with a bracketed paste. Enter isn't sent — you
review it inside the tool and send it yourself.

## Verified compatibility

| Tool | Version | Verified in this environment |
| --- | --- | --- |
| Claude Code | 2.1.287 | Launch and first-run screen in a PTY (colors, ASCII art, diff preview), redraw on a 160→120 column resize, insert mode kept while the panel layout changes. **No prompt was sent**, no paid task was started. Login and the file-writing flow were not verified in this environment. |
| Codex CLI | — | Not installed in this environment; **not verified**. Flags verified from the official source. |
| Kimi Code | — | Not installed in this environment; **not verified**. Flags verified from the official docs. |
| OpenCode | 1.18.34 | Launch screen in a PTY, project root, 160→120 column resize with Terminal mode kept, Ctrl-C reaching the tool (exit 0), output kept after exit. **No prompt was sent.** Login and the file-writing flow were not verified in this environment. |
| Test CLI (`tools/noctis-fake-ai`) | 1.0 | End to end: PTY, ANSI colors, project root, normal writes, atomic saves, create/delete, subfolders, `.gitignore`, keeps running while hidden, Ctrl-C (SIGINT), exit code, missing executable |

The test CLI passing doesn't mean all three real tools were fully tested.

## Known limits

- Changes are reviewed after they are written; there's no pre-write
  accept/reject (patch or sandbox flow) in this version.
- The source of a change can't be verified (see attribution).
- The tool's own "waiting for approval / done" state isn't read.
- The panel follows the theme; colors and control sequences inside the terminal
  belong to the tool (the 16 ANSI colors come from the theme; a theme change only
  affects new sessions).
