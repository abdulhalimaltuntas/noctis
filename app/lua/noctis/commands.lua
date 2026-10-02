-- NOCTIS command definitions (single source of truth). Every command shows up
-- in the palette; those with a key are applied as Normal mode mappings and listed in which-key.
local R = require("noctis.registry")
local U = require("noctis.util")

local function plugin(name)
  return function()
    if U.is_safe_mode() then
      return false, "plugins are disabled in safe mode"
    end
    local ok, cfg = pcall(require, "lazy.core.config")
    if not ok then
      return false, "plugins are not installed (noctis --setup)"
    end
    local p = cfg.plugins[name]
    if not p or not vim.uv.fs_stat(p.dir) then
      return false, name .. " is not installed (noctis --setup)"
    end
    return true
  end
end

local function exe(name, hint)
  return function()
    if U.has(name) then
      return true
    end
    return false, ("`%s` not found%s"):format(name, hint and (" — " .. hint) or "")
  end
end

local function lsp_attached()
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    return true
  end
  return false, "no language server attached to this buffer (:NoctisLang)"
end

local function m(mod)
  return require(mod)
end

-- ── General ──────────────────────────────────────────────────────────────
R.add({
  id = "palette",
  title = "Command palette",
  desc = "Search every command by name, description or key",
  group = "General",
  keys = "<leader><space>",
  run = function()
    m("noctis.palette").open()
  end,
})
R.add({
  id = "help",
  title = "Help and keymaps",
  desc = "Basic usage, modes and a key guide",
  group = "General",
  keys = "<leader>?",
  run = function()
    m("noctis.help").open()
  end,
})
R.add({
  id = "help.tutorial",
  title = "One-minute tour",
  desc = "Open a file, type, save, open the palette, quit safely",
  group = "General",
  keys = "<leader>ht",
  run = function()
    m("noctis.onboarding").start()
  end,
})
R.add({
  id = "help.keys",
  title = "Search all keymaps",
  desc = "List every active mapping (plugins included)",
  group = "General",
  keys = "<leader>hk",
  run = function()
    m("noctis.help").keymaps()
  end,
})
R.add({
  id = "dashboard",
  title = "Dashboard",
  desc = "Recent files, recent projects and quick actions",
  group = "General",
  keys = "<leader>hd",
  run = function()
    m("noctis.ui.dashboard").open({ force = true })
  end,
})
R.add({
  id = "health",
  title = "Health check",
  desc = "Dependencies, terminal, clipboard and AI profiles (:checkhealth noctis)",
  group = "General",
  keys = "<leader>hh",
  run = function()
    vim.cmd("checkhealth noctis")
  end,
})
R.add({
  id = "plugins",
  title = "Plugin manager",
  desc = "Lazy.nvim: status, restore from the lockfile, update",
  group = "General",
  keys = "<leader>hp",
  check = plugin("lazy.nvim"),
  run = function()
    vim.cmd("Lazy")
  end,
})
R.add({
  id = "lang",
  title = "Language packs",
  desc = "Python, JS/TS, HTML/CSS, JSON, Lua, Bash: server/parser/formatter status and install",
  group = "General",
  keys = "<leader>hl",
  run = function()
    m("noctis.lang").open()
  end,
})
R.add({
  id = "config.open",
  title = "Open user settings",
  desc = "config.lua (updates never touch this file)",
  group = "General",
  keys = "<leader>hc",
  run = function()
    m("noctis.userconfig").open()
  end,
})

-- ── File ─────────────────────────────────────────────────────────────────
R.add({
  id = "files.find",
  title = "Find file",
  desc = "Fuzzy search by file name in the project (respects .gitignore)",
  group = "File",
  keys = "<leader>ff",
  run = function()
    m("noctis.pick").files()
  end,
})
R.add({
  id = "files.find_all",
  title = "Find file (including hidden + ignored)",
  desc = "Also search files excluded by .gitignore and hidden files",
  group = "File",
  keys = "<leader>fF",
  run = function()
    m("noctis.pick").files({ hidden = true, ignored = true })
  end,
})
R.add({
  id = "files.grep",
  title = "Search text in project",
  desc = "Live search with preview; results jump to the right line",
  group = "File",
  keys = "<leader>fg",
  check = exe("rg", "install ripgrep"),
  run = function()
    m("noctis.pick").grep()
  end,
})
R.add({
  id = "files.grep_all",
  title = "Search text in project (including ignored)",
  desc = "Also search files excluded by .gitignore",
  group = "File",
  keys = "<leader>fG",
  check = exe("rg", "install ripgrep"),
  run = function()
    m("noctis.pick").grep({ hidden = true, ignored = true })
  end,
})
R.add({
  id = "files.grep_word",
  title = "Search word under cursor",
  group = "File",
  keys = "<leader>fw",
  check = exe("rg", "install ripgrep"),
  run = function()
    m("noctis.pick").grep({ word = true })
  end,
})
R.add({
  id = "files.buffers",
  title = "Search open buffers",
  group = "File",
  keys = "<leader>fb",
  run = function()
    m("noctis.pick").buffers()
  end,
})
R.add({
  id = "files.recent",
  title = "Recent files",
  group = "File",
  keys = "<leader>fr",
  run = function()
    m("noctis.pick").recent()
  end,
})
R.add({
  id = "files.save",
  title = "Save file",
  desc = "Asks first if the file was changed on disk",
  group = "File",
  keys = "<leader>fs",
  run = function()
    m("noctis.files").save()
  end,
})
R.add({
  id = "files.save_all",
  title = "Save all modified files",
  group = "File",
  keys = "<leader>fS",
  run = function()
    m("noctis.files").save_all()
  end,
})
R.add({
  id = "files.new",
  title = "New file",
  desc = "Create a file, asking for a path from the project root",
  group = "File",
  keys = "<leader>fn",
  run = function()
    m("noctis.files").new_file()
  end,
})
R.add({
  id = "files.rename",
  title = "Rename / move file",
  group = "File",
  keys = "<leader>fR",
  run = function()
    m("noctis.files").rename()
  end,
})
R.add({
  id = "files.delete",
  title = "Delete file (recoverable)",
  desc = "Asks for confirmation; the file is moved to the NOCTIS trash",
  group = "File",
  keys = "<leader>fD",
  run = function()
    m("noctis.files").delete()
  end,
})
R.add({
  id = "files.trash",
  title = "Trash: restore a deleted file",
  group = "File",
  keys = "<leader>fT",
  run = function()
    m("noctis.trash").pick()
  end,
})
R.add({
  id = "explorer",
  title = "Toggle file explorer",
  desc = "Git status, hidden files (H), ignored files (I)",
  group = "File",
  keys = "<leader>e",
  run = function()
    m("noctis.explorer").toggle()
  end,
})

-- ── Project ──────────────────────────────────────────────────────────────
R.add({
  id = "project.recent",
  title = "Recent projects",
  group = "Project",
  keys = "<leader>pp",
  run = function()
    m("noctis.project").pick_recent()
  end,
})
R.add({
  id = "project.open",
  title = "Open project (pick a folder)",
  group = "Project",
  keys = "<leader>po",
  run = function()
    m("noctis.project").open_prompt()
  end,
})
R.add({
  id = "project.set_root",
  title = "Set project root manually",
  desc = "Change the active root if the Git root is wrong or missing",
  group = "Project",
  keys = "<leader>pr",
  run = function()
    m("noctis.project").set_root_prompt()
  end,
})
R.add({
  id = "project.tasks",
  title = "Run a task (run/test/build)",
  desc = "Starts the chosen command in a terminal; nothing runs on its own",
  group = "Terminal",
  keys = "<leader>tr",
  run = function()
    m("noctis.tasks").pick()
  end,
})
R.add({
  id = "project.task_stop",
  title = "Cancel the running task",
  group = "Terminal",
  keys = "<leader>tx",
  run = function()
    m("noctis.tasks").stop()
  end,
})

-- ── Search / Replace ─────────────────────────────────────────────────────
R.add({
  id = "replace.project",
  title = "Find and replace in project (with preview)",
  desc = "Scope and every change are shown before anything is applied",
  group = "Search / Replace",
  keys = "<leader>sr",
  check = exe("rg", "install ripgrep"),
  run = function()
    m("noctis.replace").open()
  end,
})
R.add({
  id = "search.buffer",
  title = "Search lines in this file",
  group = "Search / Replace",
  keys = "<leader>sb",
  run = function()
    m("noctis.pick").lines()
  end,
})

-- ── Buffer / Window ──────────────────────────────────────────────────────
R.add({
  id = "buffer.delete",
  title = "Close buffer safely",
  desc = "Asks if there are unsaved changes; the window layout is kept",
  group = "Buffer",
  keys = "<leader>bd",
  run = function()
    m("noctis.buffers").delete()
  end,
})
R.add({
  id = "buffer.others",
  title = "Close other buffers",
  desc = "Unsaved ones stay open",
  group = "Buffer",
  keys = "<leader>bo",
  run = function()
    m("noctis.buffers").delete_others()
  end,
})
R.add({
  id = "window.vsplit",
  title = "Split vertically",
  group = "Window",
  keys = "<leader>wv",
  run = function()
    vim.cmd("vsplit")
  end,
})
R.add({
  id = "window.split",
  title = "Split horizontally",
  group = "Window",
  keys = "<leader>ws",
  run = function()
    vim.cmd("split")
  end,
})
R.add({
  id = "window.close",
  title = "Close window",
  desc = "The buffer stays open",
  group = "Window",
  keys = "<leader>wd",
  run = function()
    m("noctis.buffers").close_window()
  end,
})
R.add({
  id = "window.equal",
  title = "Equalize window sizes",
  group = "Window",
  keys = "<leader>w=",
  run = function()
    vim.cmd("wincmd =")
  end,
})

-- ── Quit / Session ───────────────────────────────────────────────────────
R.add({
  id = "quit",
  title = "Quit safely",
  desc = "Quits after showing unsaved files and running terminal/AI processes",
  group = "Quit / Session",
  keys = "<leader>qq",
  run = function()
    m("noctis.quit").quit()
  end,
})
R.add({
  id = "session.restore",
  title = "Restore project session",
  desc = "Open files and layout; never overwrites unsaved buffers",
  group = "Quit / Session",
  keys = "<leader>qr",
  run = function()
    m("noctis.session").restore()
  end,
})
R.add({
  id = "session.save",
  title = "Save session now",
  group = "Quit / Session",
  keys = "<leader>qs",
  run = function()
    m("noctis.session").save({ notify = true })
  end,
})

-- ── Terminal ─────────────────────────────────────────────────────────────
R.add({
  id = "terminal.toggle",
  title = "Toggle terminal panel",
  desc = "Hiding it doesn't kill the process; Ctrl-\\ e returns to the editor",
  group = "Terminal",
  keys = "<leader>tt",
  run = function()
    m("noctis.terminal").toggle()
  end,
})
R.add({
  id = "terminal.new",
  title = "New terminal",
  group = "Terminal",
  keys = "<leader>tn",
  run = function()
    m("noctis.terminal").new()
  end,
})
R.add({
  id = "terminal.pick",
  title = "Switch between terminals",
  group = "Terminal",
  keys = "<leader>ts",
  run = function()
    m("noctis.terminal").pick()
  end,
})

-- ── AI Workbench ─────────────────────────────────────────────────────────
R.add({
  id = "ai.toggle",
  title = "Toggle AI Workbench",
  desc = "Hiding it doesn't stop the AI process",
  group = "AI",
  keys = "<leader>aa",
  run = function()
    m("noctis.ai").toggle()
  end,
})
R.add({
  id = "ai.new",
  title = "New AI session",
  desc = "Pick a tool (Codex, Claude Code, Kimi Code, custom); the review baseline is recorded first",
  group = "AI",
  keys = "<leader>an",
  run = function()
    m("noctis.ai").new_session()
  end,
})
R.add({
  id = "ai.switch",
  title = "Switch between AI sessions",
  group = "AI",
  keys = "<leader>as",
  run = function()
    m("noctis.ai").switch()
  end,
})
R.add({
  id = "ai.review",
  title = "Review changes in the AI interval",
  desc = "File changes detected since the review baseline",
  group = "AI",
  keys = "<leader>ad",
  run = function()
    m("noctis.ai").review()
  end,
})
R.add({
  id = "ai.checkpoint",
  title = "Close the review interval, take a new baseline",
  desc = "Doesn't change any files; only records a new baseline",
  group = "AI",
  keys = "<leader>ac",
  run = function()
    m("noctis.ai").new_interval()
  end,
})
R.add({
  id = "ai.focus",
  title = "Focus the AI terminal",
  group = "AI",
  keys = "<leader>af",
  run = function()
    m("noctis.ai").focus()
  end,
})
R.add({
  id = "ai.stop",
  title = "Stop AI session",
  desc = "Asks for confirmation; the process is terminated",
  group = "AI",
  keys = "<leader>ax",
  run = function()
    m("noctis.ai").stop()
  end,
})
R.add({
  id = "ai.restart",
  title = "Restart AI session",
  group = "AI",
  keys = "<leader>ar",
  run = function()
    m("noctis.ai").restart()
  end,
})
R.add({
  id = "ai.resume",
  title = "Resume the AI tool's previous session",
  desc = "Only via the tool's documented resume flag (claude -c, codex resume --last, kimi -c)",
  group = "AI",
  keys = "<leader>aR",
  run = function()
    m("noctis.ai").new_session({ resume = true })
  end,
})
R.add({
  id = "ai.revert_hunk",
  title = "Revert this hunk to the review baseline",
  desc = "The interval change under the cursor in the editor; the disk must match the reviewed version",
  group = "AI",
  keys = "<leader>ah",
  run = function()
    m("noctis.ai.review").current_revert_hunk()
  end,
})
R.add({
  id = "ai.revert_file",
  title = "Revert this file to the review baseline",
  desc = "Asks for confirmation; refused if there is no previous content; current content is backed up first",
  group = "AI",
  keys = "<leader>aU",
  run = function()
    m("noctis.ai.review").current_revert_file()
  end,
})
R.add({
  id = "ai.reviewed",
  title = "Mark this file as reviewed",
  desc = "The mark is invalidated automatically if the content changes again",
  group = "AI",
  keys = "<leader>am",
  run = function()
    m("noctis.ai.review").current_mark_reviewed()
  end,
})
R.add({
  id = "ai.scope",
  title = "Show review scope",
  desc = "Files included in / excluded from the baseline, and limits",
  group = "AI",
  keys = "<leader>ai",
  run = function()
    m("noctis.ai").scope_info()
  end,
})
R.add({
  id = "ai.context",
  title = "Prepare selection as AI context",
  desc = "The content is shown first; nothing is sent without confirmation",
  group = "AI",
  keys = "<leader>ae",
  mode = { "n", "x" },
  run = function()
    m("noctis.ai").send_context()
  end,
})

-- ── Git ──────────────────────────────────────────────────────────────────
R.add({
  id = "git.view",
  title = "Git view",
  desc = "Opens lazygit if available; otherwise the NOCTIS Git summary",
  group = "Git",
  keys = "<leader>gg",
  run = function()
    m("noctis.git").view()
  end,
})
R.add({
  id = "git.status",
  title = "Git changed files",
  group = "Git",
  keys = "<leader>gs",
  check = exe("git"),
  run = function()
    m("noctis.git").status()
  end,
})
R.add({
  id = "git.diff_file",
  title = "File diff (Git)",
  desc = "Difference between the working tree and the index/HEAD",
  group = "Git",
  keys = "<leader>gd",
  check = exe("git"),
  run = function()
    m("noctis.git").diff_file()
  end,
})
R.add({
  id = "git.hunk_preview",
  title = "Preview hunk",
  group = "Git",
  keys = "<leader>gp",
  check = plugin("gitsigns.nvim"),
  run = function()
    require("gitsigns").preview_hunk()
  end,
})
R.add({
  id = "git.blame_line",
  title = "Blame for this line",
  group = "Git",
  keys = "<leader>gb",
  check = plugin("gitsigns.nvim"),
  run = function()
    require("gitsigns").blame_line({ full = true })
  end,
})
R.add({
  id = "git.hunk_reset",
  title = "Reset hunk (Git)",
  desc = "Asks for confirmation; only the hunk under the cursor",
  group = "Git",
  keys = "<leader>gr",
  check = plugin("gitsigns.nvim"),
  run = function()
    m("noctis.git").reset_hunk()
  end,
})

-- ── Code ─────────────────────────────────────────────────────────────────
R.add({
  id = "code.action",
  title = "Code action",
  group = "Code",
  keys = "<leader>ca",
  mode = { "n", "x" },
  check = lsp_attached,
  run = function()
    vim.lsp.buf.code_action()
  end,
})
R.add({
  id = "code.rename",
  title = "Rename symbol",
  group = "Code",
  keys = "<leader>cr",
  check = lsp_attached,
  run = function()
    vim.lsp.buf.rename()
  end,
})
R.add({
  id = "code.format",
  title = "Format file",
  group = "Code",
  keys = "<leader>cf",
  mode = { "n", "x" },
  run = function()
    m("noctis.format").format()
  end,
})
R.add({
  id = "code.definition",
  title = "Go to definition",
  group = "Code",
  keys = "<leader>cd",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("definitions")
  end,
})
R.add({
  id = "code.references",
  title = "References",
  group = "Code",
  keys = "<leader>cu",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("references")
  end,
})
R.add({
  id = "code.symbols",
  title = "Symbols in file",
  group = "Code",
  keys = "<leader>cs",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("symbols")
  end,
})
R.add({
  id = "code.hover",
  title = "Show documentation (hover)",
  desc = "Key: K",
  group = "Code",
  check = lsp_attached,
  run = function()
    vim.lsp.buf.hover()
  end,
})
R.add({
  id = "code.lsp_info",
  title = "Language server status",
  group = "Code",
  keys = "<leader>cl",
  run = function()
    vim.cmd("checkhealth vim.lsp")
  end,
})
R.add({
  id = "format.toggle",
  title = "Toggle format-on-save (filetype)",
  desc = "Off by default; applies to this session",
  group = "Code",
  keys = "<leader>uf",
  run = function()
    m("noctis.format").toggle_on_save()
  end,
})

-- ── Diagnostics ──────────────────────────────────────────────────────────
R.add({
  id = "diag.list",
  title = "Diagnostics list (project)",
  group = "Diagnostics",
  keys = "<leader>xx",
  run = function()
    m("noctis.pick").diagnostics()
  end,
})
R.add({
  id = "diag.buffer",
  title = "Diagnostics (this file)",
  group = "Diagnostics",
  keys = "<leader>xb",
  run = function()
    m("noctis.pick").diagnostics({ buffer = true })
  end,
})
R.add({
  id = "diag.line",
  title = "Show diagnostics for this line",
  group = "Diagnostics",
  keys = "<leader>xl",
  run = function()
    vim.diagnostic.open_float()
  end,
})
R.add({
  id = "diag.quickfix",
  title = "Quickfix list",
  group = "Diagnostics",
  keys = "<leader>xq",
  run = function()
    m("noctis.ui.layout").toggle_qf()
  end,
})

-- ── Interface ────────────────────────────────────────────────────────────
R.add({
  id = "ui.theme",
  title = "Pick theme",
  desc = "Midnight Violet, Glacier, Amber",
  group = "Interface",
  keys = "<leader>ut",
  run = function()
    m("noctis.theme").pick()
  end,
})
R.add({
  id = "ui.focus",
  title = "Toggle focus mode",
  desc = "Hides side panels and centers the code",
  group = "Interface",
  keys = "<leader>uz",
  run = function()
    m("noctis.ui.layout").toggle_focus()
  end,
})
R.add({
  id = "ui.relnum",
  title = "Relative line numbers",
  group = "Interface",
  keys = "<leader>un",
  run = function()
    vim.o.relativenumber = not vim.o.relativenumber
  end,
})
R.add({
  id = "ui.wrap",
  title = "Line wrap",
  group = "Interface",
  keys = "<leader>uw",
  run = function()
    vim.wo.wrap = not vim.wo.wrap
  end,
})
R.add({
  id = "ui.diagnostics",
  title = "Diagnostics visibility",
  group = "Interface",
  keys = "<leader>ud",
  run = function()
    local on = not vim.diagnostic.is_enabled()
    vim.diagnostic.enable(on)
    U.info("Diagnostics " .. (on and "shown" or "hidden"))
  end,
})
R.add({
  id = "ui.typing",
  title = "Typing animation",
  desc = "Toggle the brief glow behind typed characters (this session)",
  group = "Interface",
  keys = "<leader>ua",
  run = function()
    require("noctis.ui.typing").toggle()
  end,
})
R.add({
  id = "ui.inlay",
  title = "Inlay hints",
  group = "Interface",
  keys = "<leader>uh",
  check = lsp_attached,
  run = function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
  end,
})

return R
