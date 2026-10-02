-- Core behavior tests: configuration, keymaps, data safety.
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api

H.suite("Startup")
H.test("startup launches no AI tool or job", function()
  local s = package.loaded["noctis.ai.sessions"]
  H.ok(s == nil or #s.list == 0, "no AI session")
  local jobs = 0
  for _, ch in ipairs(vim.api.nvim_list_chans()) do
    if ch.stream == "job" then
      jobs = jobs + 1
    end
  end
  H.eq(jobs, 0, "no running job/process")
end)

H.test("leaving the dashboard gives the window its editor options back", function()
  require("noctis.ui.dashboard").open({ force = true })
  H.eq(vim.wo.number, false, "dashboard hides line numbers")
  vim.cmd("enew")
  H.eq(vim.wo.number, true, "line numbers back")
  H.eq(vim.wo.signcolumn, "yes", "sign column back")
  H.eq(vim.wo.cursorline, true, "cursorline back")
  vim.cmd("bwipeout!")
end)

-- ── Configuration ────────────────────────────────────────────────────────
H.suite("Configuration validation")
local cfg = require("noctis.config")

H.test("invalid values produce explained errors and the default is used", function()
  local errors, warnings = {}, {}
  local out = cfg.validate({
    theme = "pink",
    icons = "yes",
    ui = { explorer_width = 500, wrap = true },
    format_on_save = { enabled = true, filetypes = { "lua" } },
    themee = "glacier",
    ai = { width = 2, layout = "right" },
  }, cfg.defaults, nil, errors, warnings)
  H.eq(out.theme, "midnight-violet", "invalid theme → default")
  H.eq(out.icons, true, "wrong type → default")
  H.eq(out.ui.explorer_width, 30, "out of range → default")
  H.eq(out.ui.wrap, true, "valid sub-field is kept")
  H.eq(out.format_on_save.filetypes[1], "lua")
  H.eq(out.ai.layout, "right")
  H.eq(out.ai.width, 0.42)
  H.eq(#errors, 4, "error count: " .. vim.inspect(errors))
  H.eq(#warnings, 1, "unknown key warning")
  H.ok(warnings[1]:find("themee", 1, true))
end)

H.test("a config.lua with a syntax error doesn't break the editor; the error is visible", function()
  local path = cfg.path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  H.write(path, "return { theme = ")
  cfg.load()
  H.ok(#cfg.errors == 1 and cfg.errors[1]:find("could not be read", 1, true), vim.inspect(cfg.errors))
  H.eq(cfg.options.theme, "midnight-violet")
  H.write(path, "return { theme = 'amber' }")
  cfg.load()
  H.eq(cfg.options.theme, "amber")
  os.remove(path)
  cfg.load()
end)

-- ── Command registry and keymaps ─────────────────────────────────────────
H.suite("Command registry and keymaps")
local R = require("noctis.registry")

H.test("no conflicts or prefix problems in the default keymaps", function()
  local p = R.conflicts()
  H.eq(#p, 0, table.concat(p, "\n"))
end)

H.test("the keymap contract from the spec is applied", function()
  local spec = {
    ["<leader><space>"] = "palette",
    ["<leader>ff"] = "files.find",
    ["<leader>fg"] = "files.grep",
    ["<leader>fb"] = "files.buffers",
    ["<leader>fs"] = "files.save",
    ["<leader>e"] = "explorer",
    ["<leader>bd"] = "buffer.delete",
    ["<leader>qq"] = "quit",
    ["<leader>tt"] = "terminal.toggle",
    ["<leader>aa"] = "ai.toggle",
    ["<leader>an"] = "ai.new",
    ["<leader>as"] = "ai.switch",
    ["<leader>ad"] = "ai.review",
    ["<leader>ac"] = "ai.checkpoint",
    ["<leader>gg"] = "git.view",
    ["<leader>ca"] = "code.action",
    ["<leader>cr"] = "code.rename",
    ["<leader>cf"] = "code.format",
    ["<leader>xx"] = "diag.list",
    ["<leader>ut"] = "ui.theme",
    ["<leader>uz"] = "ui.focus",
    ["<leader>?"] = "help",
  }
  for keys, id in pairs(spec) do
    H.eq(R.by_id[id] and R.by_id[id].keys, keys, id)
    local m = vim.fn.maparg(keys:gsub("<leader>", " "), "n", false, true)
    H.ok(m and m.desc == R.by_id[id].title, "mapping not applied: " .. keys)
  end
end)

H.test("every command's availability check never throws", function()
  for _, c in ipairs(R.list) do
    local ok, reason = R.available(c)
    H.ok(ok == true or (ok == false and type(reason) == "string"), c.id)
  end
end)

H.test("core Vim keys are not remapped (i, u, /, n, dd, :)", function()
  -- Global mappings only (buffer-local keys of special buffers such as the dashboard excluded)
  local global = {}
  for _, m in ipairs(api.nvim_get_keymap("n")) do
    global[m.lhs] = true
  end
  for _, k in ipairs({ "i", "u", "/", "n", "dd", ":", "v", "p", "y", "x", "o" }) do
    H.eq(global[k], nil, "Normal mode " .. k)
  end
  H.eq(vim.fn.maparg("<Esc>", "t"), "", "in a terminal Esc goes to the application")
  H.eq(vim.fn.maparg("<C-c>", "t"), "", "in a terminal Ctrl-C goes to the application")
  H.ok(vim.fn.maparg("<C-\\>e", "t") ~= "", "a terminal → editor mapping exists")
  H.eq(vim.fn.maparg(" ", "i"), "", "space unchanged in Insert mode")
end)

H.test("user keymap override and disabling", function()
  cfg.options.keymaps = { ["files.grep"] = "<leader>/", ["ui.focus"] = false }
  H.eq(R.effective_keys(R.by_id["files.grep"]), "<leader>/")
  H.eq(R.effective_keys(R.by_id["ui.focus"]), false)
  cfg.options.keymaps = {}
end)

H.test("docs/KEYMAPS.md is up to date with the command registry", function()
  local doc = H.read(H.repo .. "/docs/KEYMAPS.md")
  H.ok(doc, "docs/KEYMAPS.md missing (tests/gen-keymaps.sh)")
  H.eq(doc, R.markdown() .. "\n", "KEYMAPS.md is stale; run tests/gen-keymaps.sh")
end)

-- ── Files and data safety ────────────────────────────────────────────────
H.suite("File editing and data safety")
local dir = H.tmpdir("core test ğüş")
vim.cmd("cd " .. vim.fn.fnameescape(dir))
require("noctis.project").refresh()

H.test("UTF-8 content is saved intact under a path with spaces/Turkish characters", function()
  local path = dir .. "/folder name/file ğüşiİöç.txt"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  api.nvim_buf_set_lines(0, 0, -1, false, { "ğüşiİöç ĞÜŞIİÖÇ", "second line" })
  require("noctis.files").save()
  H.eq(H.read(path), "ğüşiİöç ĞÜŞIİÖÇ\nsecond line\n")
  vim.cmd("bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.eq(api.nvim_buf_get_lines(0, 0, 1, false)[1], "ğüşiİöç ĞÜŞIİÖÇ")
  vim.cmd("bwipeout!")
end)

H.test("a CRLF file isn't converted needlessly; the final-line style is kept", function()
  local path = dir .. "/win.txt"
  H.write(path, "a\r\nb\r\nc")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.eq(vim.bo.fileformat, "dos")
  api.nvim_buf_set_lines(0, 1, 2, false, { "B" })
  require("noctis.files").save()
  H.eq(H.read(path), "a\r\nB\r\nc", "CRLF and the missing final newline were kept")
  vim.cmd("bwipeout!")
end)

H.test("content is kept when closing an unsaved buffer is cancelled", function()
  local path = dir .. "/kept.txt"
  H.write(path, "original\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
  local confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 3 -- Cancel
  end
  require("noctis.buffers").delete(buf)
  vim.fn.confirm = confirm
  H.ok(api.nvim_buf_is_valid(buf), "buffer stayed open")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "unsaved")
  H.eq(H.read(path), "original\n", "disk unchanged")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("safe quit lists unsaved files and doesn't quit when cancelled", function()
  local path = dir .. "/quit.txt"
  H.write(path, "x\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  api.nvim_buf_set_lines(0, 0, -1, false, { "y" })
  local seen
  local confirm = vim.fn.confirm
  vim.fn.confirm = function(msg)
    seen = msg
    return 3 -- Cancel
  end
  require("noctis.quit").quit()
  vim.fn.confirm = confirm
  H.ok(seen and seen:find("quit.txt", 1, true), "file listed: " .. tostring(seen))
  vim.bo.modified = false
  vim.cmd("bwipeout!")
end)

H.test("saving a file changed externally goes to the conflict flow (no silent overwrite)", function()
  local path = dir .. "/external.txt"
  H.write(path, "one\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "local" })
  vim.wait(20)
  H.write(path, "external program\n")
  local resolved = false
  local orig = require("noctis.sync").resolve
  require("noctis.sync").resolve = function()
    resolved = true
  end
  require("noctis.files").save(buf)
  require("noctis.sync").resolve = orig
  H.ok(resolved, "conflict resolution was called")
  H.eq(H.read(path), "external program\n", "disk not overwritten")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("an open buffer's content isn't lost when its file is deleted", function()
  local path = dir .. "/to-delete.txt"
  H.write(path, "important content\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  os.remove(path)
  require("noctis.sync").check(buf)
  H.wait(2000, function()
    return vim.bo[buf].modified and vim.b[buf].noctis_conflict ~= nil
  end, "deletion marked")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "important content")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("recoverable delete: the file moves to the trash and is restored", function()
  local path = dir .. "/trash.txt"
  H.write(path, "coming back\n")
  local ok = require("noctis.trash").move(path)
  H.ok(ok)
  H.eq(H.read(path), nil)
  local items = require("noctis.trash").list()
  H.eq(items[1].path, path)
  H.ok(require("noctis.trash").restore(items[1]))
  H.eq(H.read(path), "coming back\n")
end)

H.test("big file mode: heavy features turn off, the file stays editable", function()
  local path = dir .. "/big.py"
  H.write(path, string.rep("x = 1\n", 60000))
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.ok(vim.b.noctis_bigfile, "bigfile flag")
  vim.wait(100)
  H.eq(vim.bo.syntax, "")
  H.ok(vim.bo.modifiable, "editable")
  vim.cmd("bwipeout!")
end)

-- ── Search and replace ───────────────────────────────────────────────────
H.suite("Find and replace in project")
local replace = require("noctis.replace")

H.test("preview scope is right; applying keeps CRLF and other lines", function()
  local r = H.tmpdir("replace")
  H.write(r .. "/a.py", "foo = 1\nbar = foo\n")
  H.write(r .. "/b.txt", "foo\r\nrest\r\n")
  H.write(r .. "/c.txt", "unrelated\n")
  local changes = assert(replace.collect({ pattern = "foo", replacement = "baz", regex = false }, r))
  H.eq(#changes, 3, "3 lines")
  changes[2].on = false -- exclude the second change (a.py line 2)
  replace.apply(changes)
  H.eq(H.read(r .. "/a.py"), "baz = 1\nbar = foo\n")
  H.eq(H.read(r .. "/b.txt"), "baz\r\nrest\r\n")
  H.eq(H.read(r .. "/c.txt"), "unrelated\n")
end)

H.test("a line changed after the preview is skipped when applying", function()
  local r = H.tmpdir("replace2")
  H.write(r .. "/a.txt", "foo\nfoo\n")
  local changes = assert(replace.collect({ pattern = "foo", replacement = "bar", regex = false }, r))
  H.write(r .. "/a.txt", "foo\nsomeone else changed this\n")
  replace.apply(changes)
  H.eq(H.read(r .. "/a.txt"), "bar\nsomeone else changed this\n")
end)

H.test("regex mode with ripgrep group syntax: preview = apply", function()
  local r = H.tmpdir("replace3")
  H.write(r .. "/a.js", "getUser(1)\ngetItem(2)\n")
  local changes = assert(replace.collect({ pattern = [[get(\w+)\(]], replacement = "fetch$1(", regex = true }, r))
  H.eq(changes[1].new, "fetchUser(1)")
  replace.apply(changes)
  H.eq(H.read(r .. "/a.js"), "fetchUser(1)\nfetchItem(2)\n")
end)

-- ── Hunk arithmetic ──────────────────────────────────────────────────────
H.suite("Hunk revert precision")
local hunks = require("noctis.ai.hunks")
H.test("insert/delete/final-newline differences revert byte-exactly", function()
  local cases = {
    { "a\nb\nc\n", "a\nX\nb\nc\n" },
    { "a\nb\nc\n", "a\nc\n" },
    { "a\nb\n", "X\na\nb\n" },
    { "a\nb\n", "a\nb\nZ\n" },
    { "a\nb", "a\nb\n" },
    { "a\r\nb\r\n", "a\r\nB\r\n" },
    { "", "new\n" },
  }
  for i, c in ipairs(cases) do
    local base, cur = c[1], c[2]
    local hk = hunks.diff(base, cur)
    local text = cur
    for j = #hk, 1, -1 do
      text = hunks.revert_hunk(base, text, hunks.diff(base, text)[j] or hk[j])
    end
    H.eq(text, base, "case " .. i)
  end
end)

-- ── Session and terminal ─────────────────────────────────────────────────
H.suite("Session and terminal")
H.test("saving and restoring a session never overwrites an unsaved buffer", function()
  local r = H.tmpdir("session")
  vim.cmd("cd " .. vim.fn.fnameescape(r))
  require("noctis.project").refresh()
  H.write(r .. "/x.txt", "x\n")
  H.write(r .. "/y.txt", "y\n")
  vim.cmd("silent! %bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(r .. "/x.txt"))
  vim.cmd("vsplit " .. vim.fn.fnameescape(r .. "/y.txt"))
  require("noctis.session").save()
  vim.cmd("only")
  vim.cmd("edit " .. vim.fn.fnameescape(r .. "/x.txt"))
  api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved x" })
  require("noctis.session").restore()
  H.eq(#api.nvim_tabpage_list_wins(0), 2, "split layout restored")
  local xb = vim.fn.bufnr(r .. "/x.txt")
  H.eq(api.nvim_buf_get_lines(xb, 0, 1, false)[1], "unsaved x", "modified buffer kept")
  vim.bo[xb].modified = false
end)

H.test("hiding the terminal panel keeps the process and its output", function()
  local term = require("noctis.terminal")
  local t = term.new({ cmd = { "sh", "-c", "echo NOCTIS_TERM_OK; exec sleep 30" } })
  H.wait(3000, function()
    return table.concat(api.nvim_buf_get_lines(t.buf, 0, -1, false), "\n"):find("NOCTIS_TERM_OK", 1, true) ~= nil
  end, "output")
  term.hide()
  H.ok(not term.is_visible())
  H.ok(vim.fn.jobpid(t.job) > 0, "process alive")
  term.show()
  H.eq(api.nvim_win_get_buf(term.win), t.buf, "back to the same session")
  H.ok(table.concat(api.nvim_buf_get_lines(t.buf, 0, -1, false), "\n"):find("NOCTIS_TERM_OK", 1, true), "output kept")
  H.ok(#require("noctis.quit").running() >= 1, "the quit summary sees the running terminal")
  vim.fn.jobstop(t.job)
  term.hide()
end)

H.test("terminal child processes don't inherit the NOCTIS-specific environment", function()
  local env = require("noctis.util").child_env()
  H.eq(env.NOCTIS_HOME, nil)
  H.eq(env.NVIM_APPNAME, vim.env.NOCTIS_ORIG_NVIM_APPNAME)
end)

H.test("task detection builds commands from the project but runs nothing", function()
  local r = H.tmpdir("tasks")
  H.write(r .. "/package.json", '{"scripts":{"test":"echo t","build":"echo b"}}')
  H.write(r .. "/Makefile", "all:\n\techo all\nlint:\n\techo lint\n")
  vim.cmd("cd " .. vim.fn.fnameescape(r))
  require("noctis.project").refresh()
  local list = require("noctis.tasks").list()
  local names = {}
  for _, t in ipairs(list) do
    names[t.source .. ":" .. t.name] = table.concat(t.cmd, " ")
  end
  H.eq(names["npm:test"], "npm run test")
  H.eq(names["make:lint"], "make lint")
  H.eq(#require("noctis.tasks").running(), 0)
end)

-- ── Typing animation ─────────────────────────────────────────────────────
H.suite("Typing animation")
local typing = require("noctis.ui.typing")

local function glows(buf)
  return vim.api.nvim_buf_get_extmarks(buf or 0, typing.ns, 0, -1, { details = true })
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(20) -- InsertCharPre → scheduled placement
end

H.test("every typed character glows, fades and leaves no trace; syntax color is kept", function()
  vim.o.termguicolors = true
  typing.refresh()
  H.ok(typing.active(), "active with truecolor")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  type_keys("iab c<Esc>")
  local marks = glows(buf)
  H.eq(#marks, 3, "every character except the space")
  H.eq(marks[1][4].hl_group, "NoctisType1")
  local hl = vim.api.nvim_get_hl(0, { name = "NoctisType1" })
  H.ok(hl.bg ~= nil and hl.fg == nil, "background only; the foreground (syntax) is unchanged")
  H.wait(1000, function()
    return #glows(buf) == 0 and typing.live_count() == 0
  end, "animation finished")
  H.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "ab c", "text unchanged")
  vim.cmd("bwipeout!")
end)

H.test("pastes/bursts, macros and big files are not animated", function()
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  type_keys("i" .. string.rep("x", 40) .. "<Esc>")
  H.eq(#glows(buf), 0, "40 characters at once = a paste")
  vim.fn.setreg("q", "Ayz\27")
  type_keys("@q")
  H.eq(#glows(buf), 0, "macro")
  vim.cmd("bwipeout!")
  local path = H.tmpdir("anim") .. "/big.txt"
  H.write(path, string.rep("line\n", 60000))
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.ok(vim.b.noctis_bigfile)
  type_keys("ggOab<Esc>")
  H.eq(#glows(), 0, "big file")
  vim.cmd("bwipeout!")
end)

H.test("can be turned off; disabled automatically in 256-color mode", function()
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  typing.toggle()
  H.ok(not typing.active(), "turned off by the command")
  type_keys("iab<Esc>")
  H.eq(#glows(buf), 0)
  typing.toggle()
  H.ok(typing.active(), "turned back on")
  vim.o.termguicolors = false
  H.wait(500, function()
    return not typing.active()
  end, "disabled when termguicolors turns off")
  type_keys("Acd<Esc>")
  H.eq(#glows(buf), 0)
  vim.o.termguicolors = true
  H.wait(500, function()
    return typing.active()
  end, "active again once truecolor is back")
  vim.cmd("bwipeout!")
end)

H.suite("Theme and contrast")

H.test("every theme passes the contrast audit (AA text, 3:1 dim text, 2:1 popup borders)", function()
  local problems = require("noctis.theme").audit()
  local lines = {}
  for i = 1, math.min(#problems, 10) do
    local p = problems[i]
    lines[#lines + 1] = ("%s %s %.2f < %.1f (%s on %s)"):format(p.theme, p.group, p.ratio, p.min, p.fg, p.bg)
  end
  H.eq(#problems, 0, "low-contrast pairs:\n" .. table.concat(lines, "\n"))
end)

H.test("each variant sets 'background'; Daybreak is light and its terminal palette stays readable", function()
  local theme = require("noctis.theme")
  local tokens = require("noctis.theme.tokens")
  theme.apply("daybreak")
  H.eq(vim.o.background, "light")
  H.eq(vim.g.colors_name, "daybreak")
  -- ANSI "black" is dark and "white" a readable grey on the light ground
  H.ok(tokens.contrast(vim.g.terminal_color_0, theme.tokens.bg) >= 4.5, "color0 readable")
  H.ok(tokens.contrast(vim.g.terminal_color_7, theme.tokens.bg) >= 4.5, "color7 readable")
  for _, name in ipairs({ "midnight-violet", "glacier", "amber" }) do
    theme.apply(name)
    H.eq(vim.o.background, "dark", name)
  end
  theme.apply("midnight-violet")
end)

H.test(":set background=light switches to Daybreak; dark returns to the last dark theme", function()
  local theme = require("noctis.theme")
  vim.cmd("colorscheme glacier")
  H.eq(vim.g.colors_name, "glacier")
  vim.o.background = "light"
  H.eq(vim.g.colors_name, "daybreak")
  H.eq(vim.o.background, "light")
  vim.o.background = "dark"
  H.eq(vim.g.colors_name, "glacier", "back to the dark theme in use before")
  -- an explicit :colorscheme is respected as is
  vim.cmd("colorscheme amber")
  H.eq(vim.g.colors_name, "amber")
  H.eq(vim.o.background, "dark")
  theme.apply("midnight-violet")
end)

H.test("transparent mode: no editor background; the cursor line is a tint, not a dark band", function()
  local cfg = require("noctis.config").options
  local theme = require("noctis.theme")
  local tokens = require("noctis.theme.tokens")
  cfg.transparent = true
  theme.apply("midnight-violet")
  H.eq(vim.api.nvim_get_hl(0, { name = "Normal" }).bg, nil, "Normal bg is NONE")
  local cl = ("#%06X"):format(vim.api.nvim_get_hl(0, { name = "CursorLine" }).bg)
  local p = require("noctis.theme.palettes")["midnight-violet"]
  H.eq(cl, tokens.blend(p.accent, p.bg, 0.10))
  cfg.transparent = false
  theme.apply("midnight-violet")
end)

H.test("code punctuation and popup borders no longer reuse the UI chrome grey", function()
  local theme = require("noctis.theme")
  theme.apply("midnight-violet")
  local function fg(g)
    return vim.api.nvim_get_hl(0, { name = g, link = false }).fg
  end
  local muted = tonumber(theme.tokens.muted:sub(2), 16)
  H.ok(fg("Delimiter") ~= muted, "Delimiter")
  H.ok(fg("Operator") ~= muted and fg("Operator") ~= fg("Delimiter"), "Operator has its own tone")
  H.ok(fg("@punctuation.bracket") == fg("Delimiter"), "brackets match delimiters")
  local border = tonumber(theme.tokens.border:sub(2), 16)
  H.ok(fg("FloatBorder") ~= border, "popup border is not the separator color")
end)

H.done()
