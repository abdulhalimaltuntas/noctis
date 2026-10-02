# NOCTIS keymaps and commands

> This file is generated from the command registry in `app/lua/noctis/commands.lua`
> (`tests/gen-keymaps.sh`). Don't edit it by hand; the test suite checks that it's up to date.

Every command can be found by name in the `Space Space` command palette. The table is for Normal mode.

## General

| Key | Command | Description |
| --- | --- | --- |
| `Space Space` | Command palette | Search every command by name, description or key |
| `Space ?` | Help and keymaps | Basic usage, modes and a key guide |
| `Space h t` | One-minute tour | Open a file, type, save, open the palette, quit safely |
| `Space h k` | Search all keymaps | List every active mapping (plugins included) |
| `Space h d` | Dashboard | Recent files, recent projects and quick actions |
| `Space h h` | Health check | Dependencies, terminal, clipboard and AI profiles (:checkhealth noctis) |
| `Space h p` | Plugin manager | Lazy.nvim: status, restore from the lockfile, update |
| `Space h l` | Language packs | Python, JS/TS, HTML/CSS, JSON, Lua, Bash: server/parser/formatter status and install |
| `Space h c` | Open user settings | config.lua (updates never touch this file) |

## File

| Key | Command | Description |
| --- | --- | --- |
| `Space f f` | Find file | Fuzzy search by file name in the project (respects .gitignore) |
| `Space f F` | Find file (including hidden + ignored) | Also search files excluded by .gitignore and hidden files |
| `Space f g` | Search text in project | Live search with preview; results jump to the right line |
| `Space f G` | Search text in project (including ignored) | Also search files excluded by .gitignore |
| `Space f w` | Search word under cursor |  |
| `Space f b` | Search open buffers |  |
| `Space f r` | Recent files |  |
| `Space f s` | Save file | Asks first if the file was changed on disk |
| `Space f S` | Save all modified files |  |
| `Space f n` | New file | Create a file, asking for a path from the project root |
| `Space f R` | Rename / move file |  |
| `Space f D` | Delete file (recoverable) | Asks for confirmation; the file is moved to the NOCTIS trash |
| `Space f T` | Trash: restore a deleted file |  |
| `Space e` | Toggle file explorer | Git status, hidden files (H), ignored files (I) |

## Project

| Key | Command | Description |
| --- | --- | --- |
| `Space p p` | Recent projects |  |
| `Space p o` | Open project (pick a folder) |  |
| `Space p r` | Set project root manually | Change the active root if the Git root is wrong or missing |

## Terminal

| Key | Command | Description |
| --- | --- | --- |
| `Space t r` | Run a task (run/test/build) | Starts the chosen command in a terminal; nothing runs on its own |
| `Space t x` | Cancel the running task |  |
| `Space t t` | Toggle terminal panel | Hiding it doesn't kill the process; Ctrl-\ e returns to the editor |
| `Space t n` | New terminal |  |
| `Space t s` | Switch between terminals |  |

## Search / Replace

| Key | Command | Description |
| --- | --- | --- |
| `Space s r` | Find and replace in project (with preview) | Scope and every change are shown before anything is applied |
| `Space s b` | Search lines in this file |  |

## Buffer

| Key | Command | Description |
| --- | --- | --- |
| `Space b d` | Close buffer safely | Asks if there are unsaved changes; the window layout is kept |
| `Space b o` | Close other buffers | Unsaved ones stay open |

## Window

| Key | Command | Description |
| --- | --- | --- |
| `Space w v` | Split vertically |  |
| `Space w s` | Split horizontally |  |
| `Space w d` | Close window | The buffer stays open |
| `Space w =` | Equalize window sizes |  |

## Quit / Session

| Key | Command | Description |
| --- | --- | --- |
| `Space q q` | Quit safely | Quits after showing unsaved files and running terminal/AI processes |
| `Space q r` | Restore project session | Open files and layout; never overwrites unsaved buffers |
| `Space q s` | Save session now |  |

## AI

| Key | Command | Description |
| --- | --- | --- |
| `Space a a` | Toggle AI Workbench | Hiding it doesn't stop the AI process |
| `Space a n` | New AI session | Pick a tool (Claude Code, Codex, Kimi Code, OpenCode, custom); the review baseline is recorded first |
| `Space a s` | Switch between AI sessions |  |
| `Space a d` | Review changes in the AI interval | File changes detected since the review baseline |
| `Space a c` | Close the review interval, take a new baseline | Doesn't change any files; only records a new baseline |
| `Space a f` | Focus the AI terminal |  |
| `Space a x` | Stop AI session | Asks for confirmation; the process is terminated |
| `Space a r` | Restart AI session |  |
| `Space a R` | Resume the AI tool's previous session | Only via the tool's documented resume flag (claude -c, codex resume --last, kimi -c, opencode -c) |
| `Space a h` | Revert this hunk to the review baseline | The interval change under the cursor in the editor; the disk must match the reviewed version |
| `Space a U` | Revert this file to the review baseline | Asks for confirmation; refused if there is no previous content; current content is backed up first |
| `Space a m` | Mark this file as reviewed | The mark is invalidated automatically if the content changes again |
| `Space a i` | Show review scope | Files included in / excluded from the baseline, and limits |
| `Space a e` | Prepare selection as AI context | The content is shown first; nothing is sent without confirmation |

## Git

| Key | Command | Description |
| --- | --- | --- |
| `Space g g` | Git view | Opens lazygit if available; otherwise the NOCTIS Git summary |
| `Space g s` | Git changed files |  |
| `Space g d` | File diff (Git) | Difference between the working tree and the index/HEAD |
| `Space g p` | Preview hunk |  |
| `Space g b` | Blame for this line |  |
| `Space g r` | Reset hunk (Git) | Asks for confirmation; only the hunk under the cursor |

## Code

| Key | Command | Description |
| --- | --- | --- |
| `Space c a` | Code action |  |
| `Space c r` | Rename symbol |  |
| `Space c f` | Format file |  |
| `Space c d` | Go to definition |  |
| `Space c u` | References |  |
| `Space c s` | Symbols in file |  |
| — | Show documentation (hover) | Key: K |
| `Space c l` | Language server status |  |
| `Space u f` | Toggle format-on-save (filetype) | Off by default; applies to this session |

## Diagnostics

| Key | Command | Description |
| --- | --- | --- |
| `Space x x` | Diagnostics list (project) |  |
| `Space x b` | Diagnostics (this file) |  |
| `Space x l` | Show diagnostics for this line |  |
| `Space x q` | Quickfix list |  |

## Interface

| Key | Command | Description |
| --- | --- | --- |
| `Space u t` | Pick theme | Midnight Violet, Glacier, Amber |
| `Space u z` | Toggle focus mode | Hides side panels and centers the code |
| `Space u n` | Relative line numbers |  |
| `Space u w` | Line wrap |  |
| `Space u d` | Diagnostics visibility |  |
| `Space u a` | Typing animation | Toggle the brief glow behind typed characters (this session) |
| `Space u h` | Inlay hints |  |

