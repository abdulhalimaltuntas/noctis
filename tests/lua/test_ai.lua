-- AI Workbench change tracking: deterministic tests (with the fake CLI).
-- Covers acceptance criteria 13–20. No real AI service is contacted.
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local U = require("noctis.util")
local api = vim.api

local tracker = require("noctis.ai.tracker")
local review = require("noctis.ai.review")
local store = require("noctis.ai.store")
local hunks = require("noctis.ai.hunks")

local function file_lines(n, prefix)
  local t = {}
  for i = 1, n do
    t[#t + 1] = ("%s line %d"):format(prefix or "x", i)
  end
  return table.concat(t, "\n") .. "\n"
end

local function ensure(root)
  local got
  tracker.ensure(root, function(t)
    got = t
  end)
  H.wait(20000, function()
    return got ~= nil
  end, "baseline")
  return got
end

local function wait_change(t, rel, kind, ms)
  H.wait(ms or 5000, function()
    local ch = t.changes[rel]
    if kind == nil then
      return ch == nil
    end
    return ch ~= nil and ch.kind == kind
  end, ("%s → %s"):format(rel, tostring(kind)))
end

-- ── Git project ──────────────────────────────────────────────────────────
H.suite("AI tracking: Git project (path with spaces and Turkish characters)")
local root = H.tmpdir("project ğüşiİöç")
H.init_repo(root)
H.write(root .. "/a.py", file_lines(20, "a"))
H.write(root .. "/b.txt", "b content\n")
H.write(root .. "/keep.txt", "to be kept\n")
H.write(root .. "/staged.txt", "old\n")
H.write(root .. "/sub/c.py", "print('c')\n")
H.write(root .. "/crlf.txt", "one\r\ntwo\r\nthree\r\n")
H.write(root .. "/.gitignore", "logs/\n")
H.write(root .. "/.env", "TOKEN=secret\n")
H.write(root .. "/bin.dat", "PNG\0\1\2\3binary")
H.write(root .. "/big.bin", string.rep("Z", 1100 * 1024))
H.git(root, "add", "a.py", "b.txt", "keep.txt", "staged.txt", "sub/c.py", "crlf.txt", ".gitignore")
H.git(root, "commit", "-q", "-m", "first")
-- User changes that existed before the baseline
H.write(root .. "/staged.txt", "staged new\n")
H.git(root, "add", "staged.txt")
H.write(root .. "/keep.txt", "to be kept (unstaged edit)\n")
H.write(root .. "/untracked.txt", "untracked\n")
local index_before = H.read(root .. "/.git/index")
local status_before = H.git(root, "status", "--porcelain")
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()

local t
H.test("the baseline is recorded; the Git index and working tree don't change", function()
  local t0 = vim.uv.hrtime()
  t = ensure(root)
  H.note(("baseline: %d files, %.0f ms"):format(t.interval.stats.captured, (vim.uv.hrtime() - t0) / 1e6))
  H.eq(H.read(root .. "/.git/index"), index_before, "index bytes")
  H.eq(H.git(root, "status", "--porcelain"), status_before, "git status")
  H.eq(H.read(root .. "/staged.txt"), "staged new\n")
end)

H.test("pre-existing staged/unstaged/untracked content is part of the baseline, not a new change", function()
  local f = t.interval.files
  H.ok(f["staged.txt"] and f["staged.txt"].hash, "staged.txt recorded")
  H.ok(f["keep.txt"] and f["keep.txt"].hash, "keep.txt recorded")
  H.ok(f["untracked.txt"] and f["untracked.txt"].hash, "untracked.txt recorded")
  H.eq(store.get_blob(root, f["keep.txt"].hash), "to be kept (unstaged edit)\n", "disk content stored (not just a hash)")
  H.eq(vim.tbl_count(t.changes), 0, "no changes at the baseline")
  H.ok(#(t.interval.git.entries or {}) >= 3, "git state recorded")
end)

H.test("scope: sensitive, large and binary files are classified correctly", function()
  local f = t.interval.files
  H.eq(f[".env"] and f[".env"].reason, "sensitive", ".env")
  H.eq(f[".env"].hash, nil, ".env content not copied")
  H.eq(f["big.bin"] and f["big.bin"].reason, "large", "big.bin")
  H.ok(f["bin.dat"] and f["bin.dat"].binary, "bin.dat binary")
  H.eq(f["logs/x"], nil)
end)

H.test("a normal write shows up within ~1 s; line counts are right", function()
  local new = file_lines(20, "a"):gsub("a line 3\n", "a line 3 AI\n")
  local t_written = H.fake_batch(root, "write a.py " .. new:gsub("\n", "\\n"))
  wait_change(t, "a.py", "modified")
  local ms = (vim.uv.hrtime() - t_written) / 1e6
  H.note(("from write to visible update: %.0f ms"):format(ms))
  H.ok(ms < 1500, "latency < 1500 ms")
  H.eq(t.changes["a.py"].adds, 1)
  H.eq(t.changes["a.py"].dels, 1)
end)

H.test("atomic save (temp file + rename): one change, the temp file never stays listed", function()
  H.fake_batch(root, "atomic b.txt b new\\n")
  wait_change(t, "b.txt", "modified")
  vim.wait(600)
  for rel in pairs(t.changes) do
    H.ok(not rel:find("%.tmp"), "temp file listed: " .. rel)
  end
end)

H.test("file creation, deletion and a new subfolder are tracked", function()
  H.fake_batch(root, "write new.py print(1)\\n", "delete keep.txt", "write fresh/deep/x.py x = 1\\n")
  wait_change(t, "new.py", "added")
  wait_change(t, "keep.txt", "deleted")
  wait_change(t, "fresh/deep/x.py", "added")
  -- later writes under the new folder are tracked too
  H.fake_batch(root, "write fresh/deep/y.py y = 2\\n")
  wait_change(t, "fresh/deep/y.py", "added")
end)

H.test("paths excluded by .gitignore don't enter the list", function()
  H.fake_batch(root, "write logs/out.log journal\\n", "write z_marker.txt marker\\n")
  wait_change(t, "z_marker.txt", "added")
  vim.wait(400)
  H.eq(t.changes["logs/out.log"], nil)
end)

H.test("a sensitive file change is reported but has no content/diff", function()
  H.fake_batch(root, "write .env TOKEN=new\\n")
  wait_change(t, ".env", "modified")
  H.eq(t.changes[".env"].no_baseline, "sensitive")
end)

H.test("a clean buffer reloads with the settled disk content; the cursor is kept", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/sub/c.py"))
  local buf = api.nvim_get_current_buf()
  H.fake_batch(root, "write sub/c.py print('c')\\nprint('AI')\\n")
  H.wait(5000, function()
    return api.nvim_buf_get_lines(buf, 0, -1, false)[2] == "print('AI')"
  end, "buffer reloaded")
  H.eq(vim.bo[buf].modified, false)
  H.eq(vim.b[buf].noctis_conflict, nil)
end)

H.test("an unsaved buffer is never auto-reloaded/saved; a conflict is marked; both contents kept", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/crlf.txt"))
  local buf = api.nvim_get_current_buf()
  H.eq(vim.bo[buf].fileformat, "dos", "CRLF detected")
  api.nvim_buf_set_lines(buf, 0, 1, false, { "one (local edit)" })
  H.ok(vim.bo[buf].modified)
  H.fake_batch(root, "write crlf.txt one\\r\\ntwo\\r\\nthree (AI)\\r\\n")
  wait_change(t, "crlf.txt", "modified")
  H.wait(3000, function()
    return vim.b[buf].noctis_conflict ~= nil
  end, "conflict mark")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "one (local edit)", "local edit kept")
  H.eq(H.read(root .. "/crlf.txt"), "one\r\ntwo\r\nthree (AI)\r\n", "disk content not overwritten")
  H.ok(require("noctis.sync").disk_changed(buf), "the disk is re-checked on save")
end)

H.test("a 3-way merge on conflict keeps both sides (base: last sync)", function()
  local buf = vim.fn.bufnr(root .. "/crlf.txt")
  require("noctis.sync").merge(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  H.eq(lines[1], "one (local edit)")
  H.eq(lines[3], "three (AI)")
  H.eq(vim.b[buf].noctis_conflict, nil, "a clean merge clears the conflict")
  vim.api.nvim_buf_call(buf, function()
    require("noctis.files").save(buf)
  end)
  H.eq(vim.bo[buf].modified, false, "saved (without a prompt)")
  H.eq(H.read(root .. "/crlf.txt"), "one (local edit)\r\ntwo\r\nthree (AI)\r\n", "saved with CRLF kept")
end)

H.test("reverting a selected hunk changes only that hunk; the index is kept", function()
  local base = file_lines(30, "h")
  H.write(root .. "/h.py", base)
  -- h.py didn't exist at the baseline; start a new interval to include it
  local done
  tracker.new_interval(root, function(nt)
    done = nt
  end)
  H.wait(20000, function()
    return done ~= nil
  end, "new interval")
  t = done
  local idx = H.read(root .. "/.git/index")
  local cur = base:gsub("h line 3\n", "h line 3 AI\n"):gsub("h line 25\n", "h line 25 AI\n")
  H.fake_batch(root, "write h.py " .. cur:gsub("\n", "\\n"))
  wait_change(t, "h.py", "modified")
  local disk = H.read(root .. "/h.py")
  local hk = hunks.diff(base, disk)
  H.eq(#hk, 2, "two hunks")
  local ok = review.revert_hunk(t, "h.py", store.hash(disk), hk[2])
  H.ok(ok, "reverted")
  local after = H.read(root .. "/h.py")
  H.ok(after:find("h line 3 AI", 1, true), "first hunk kept")
  H.ok(not after:find("h line 25 AI", 1, true), "second hunk reverted")
  H.eq(H.read(root .. "/.git/index"), idx, "index unchanged")
end)

H.test("if the file changes after review, the revert is never done blindly", function()
  local viewed = store.hash(H.read(root .. "/h.py"))
  H.fake_batch(root, "append h.py last line (second AI write)\\n")
  vim.wait(50)
  local before = H.read(root .. "/h.py")
  local ok = review.revert_file(t, "h.py", viewed)
  H.eq(ok, false, "refused")
  H.eq(H.read(root .. "/h.py"), before, "disk unchanged")
end)

H.test("a revert is refused while the buffer has unsaved edits", function()
  wait_change(t, "h.py", "modified")
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/h.py"))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, 1, false, { "user edit" })
  local disk = H.read(root .. "/h.py")
  local ok = review.revert_file(t, "h.py", store.hash(disk))
  H.eq(ok, false)
  H.eq(H.read(root .. "/h.py"), disk)
  vim.cmd("edit!")
end)

H.test("a file without previous content (out of scope) isn't reverted, and the reason is given", function()
  H.fake_batch(root, "append big.bin EXTRA")
  wait_change(t, "big.bin", "modified")
  H.eq(t.changes["big.bin"].no_baseline, "large")
  local disk = H.read(root .. "/big.bin")
  H.eq(review.revert_file(t, "big.bin", store.hash(disk)), false)
  H.eq(H.read(root .. "/big.bin"), disk)
end)

H.test("the reviewed mark is invalidated when the content changes again", function()
  H.fake_batch(root, "write r.py r = 1\\n")
  wait_change(t, "r.py", "added")
  t:mark_reviewed("r.py", true)
  H.ok(t:is_reviewed("r.py"))
  H.fake_batch(root, "write r.py r = 2\\n")
  H.wait(5000, function()
    return not t:is_reviewed("r.py")
  end, "mark invalidated")
end)

H.test("the change list never attributes changes to a tool; the two comparisons are labeled separately", function()
  review.set_root(root)
  local buf = review.ensure_list_buf()
  review.mode = "interval"
  review.render()
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(text:find("which program wrote them is not verified", 1, true), "source warning")
  H.ok(not text:find("Claude", 1, true) and not text:find("Codex", 1, true), "no tool name attributed")
  review.mode = "git"
  review.render()
  local gtext = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(gtext:find("Git changes (vs HEAD)", 1, true), "separate Git view")
  review.mode = "interval"
end)

H.test("a new interval doesn't change files and resets the change list", function()
  local snap = H.read(root .. "/a.py")
  local done
  tracker.new_interval(root, function(nt)
    done = nt
  end)
  H.wait(20000, function()
    return done ~= nil
  end)
  t = done
  H.eq(H.read(root .. "/a.py"), snap)
  H.eq(vim.tbl_count(t.changes), 0)
end)

-- ── PTY session (fake CLI) ───────────────────────────────────────────────
H.suite("AI session: real PTY + fake CLI")
require("noctis.config").options.ai.profiles.fake = { label = "Fake AI", cmd = { H.fake } }
require("noctis.config").options.ai.profiles.missing = { label = "Missing Tool", cmd = { "noctis-nonexistent-tool-xyz" } }
local sessions = require("noctis.ai.sessions")

H.test("a session starts at the project root, becomes 'running' on evidence of output, file writes are tracked", function()
  local profile = require("noctis.ai.profiles").get("fake")
  local win = require("noctis.ai.workbench").prepare_window()
  local s, err = sessions.start(profile, root, win, {})
  H.ok(s, err)
  H.wait(5000, function()
    return s.status == "running"
  end, "running")
  H.wait(3000, function()
    local txt = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "")
    return txt:find("cwd:", 1, true) ~= nil
  end, "banner")
  local banner = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "")
  H.ok(banner:find(vim.fn.fnamemodify(root, ":t"), 1, true), "cwd is the project root")
  vim.fn.chansend(s.job, "write pty.txt hello\n")
  wait_change(t, "pty.txt", "added")
  -- The process keeps running while the panel is hidden
  require("noctis.ai.workbench").hide()
  vim.fn.chansend(s.job, "write pty2.txt while-hidden\n")
  wait_change(t, "pty2.txt", "added")
  H.ok(sessions.alive(s), "process alive")
  vim.fn.chansend(s.job, "exit 3\n")
  H.wait(5000, function()
    return s.status == "exited"
  end, "exited")
  H.eq(s.code, 3)
  H.eq(sessions.status_text(s), "exited (3)")
end)

H.test("two sessions in one working tree: a concurrent-write warning shows, no source is attributed", function()
  local profile = require("noctis.ai.profiles").get("fake")
  local wb = require("noctis.ai.workbench")
  local s1 = assert(sessions.start(profile, root, wb.prepare_window(), {}))
  local s2 = assert(sessions.start(profile, root, wb.prepare_window(), {}))
  H.wait(5000, function()
    return s1.status == "running" and s2.status == "running"
  end, "two sessions")
  H.eq(#sessions.running(root), 2)
  review.set_root(root)
  review.ensure_list_buf()
  review.mode = "interval"
  review.render()
  local text = table.concat(api.nvim_buf_get_lines(review.list_buf, 0, -1, false), "\n")
  H.ok(text:find("2 AI sessions are running in the same working tree", 1, true), "warning")
  wb.current = s1.id
  H.ok(wb.winbar():find("2 tools", 1, true), "panel warning (never dropped, even when narrow)")
  vim.fn.chansend(s1.job, "write shared.txt one\n")
  wait_change(t, "shared.txt", "added")
  H.eq(t.changes["shared.txt"].source, nil, "the change isn't attributed to a session")
  sessions.stop(s1)
  sessions.stop(s2)
  H.wait(5000, function()
    return s1.status == "exited" and s2.status == "exited"
  end)
end)

H.test("built-in OpenCode profile: found on PATH, version query, --continue resume, tracked writes", function()
  -- A shim named `opencode` first on PATH: records its arguments, then runs the
  -- test CLI. The real OpenCode needs network and an account, so it isn't used here.
  local shimdir = H.tmpdir("opencode shim")
  local shim = shimdir .. "/opencode"
  H.write(shim, table.concat({
    "#!/bin/sh",
    'if [ "$1" = "--version" ]; then echo "opencode-shim 9.9.9"; exit 0; fi',
    'printf "%s\\n" "$@" > "$SHIM_ARGS"',
    'exec python3 "$SHIM_FAKE"',
  }, "\n") .. "\n")
  vim.uv.fs_chmod(shim, 493)
  local path_before = vim.env.PATH
  vim.env.PATH = shimdir .. ":" .. path_before
  vim.env.SHIM_ARGS, vim.env.SHIM_FAKE = shimdir .. "/args", H.fake

  local P = require("noctis.ai.profiles")
  local _, order = P.all()
  H.ok(vim.tbl_contains(order, "opencode"), "listed among the built-in profiles")
  local p = P.get("opencode")
  H.eq(p.label, "OpenCode")
  H.eq(P.resolve(p), shim, "executable resolved from PATH")
  local version
  P.version(p, function(v)
    version = v or "error"
  end)
  H.wait(5000, function()
    return version ~= nil
  end, "version query")
  H.eq(version, "opencode-shim 9.9.9")

  local s = assert(sessions.start(p, root, require("noctis.ai.workbench").prepare_window(), { resume = true }))
  H.wait(5000, function()
    return s.status == "running"
  end, "running")
  H.eq(H.read(shimdir .. "/args"), "--continue\n", "resume uses the verified --continue flag")
  vim.fn.chansend(s.job, "write opencode.txt hello\n")
  wait_change(t, "opencode.txt", "added")

  -- Focusing asks for Terminal mode only while the tool runs: in an exited
  -- terminal any key in Terminal mode would delete the buffer and the tool's
  -- last output. (Headless Neovim can't really enter Terminal mode, so the
  -- request itself is observed; the key behavior is verified in a real PTY.)
  local wb = require("noctis.ai.workbench")
  local inserts = 0
  local cmd = vim.cmd
  vim.cmd = setmetatable({}, {
    __index = cmd,
    __call = function(_, c, ...)
      if c == "startinsert" then
        inserts = inserts + 1
      end
      return cmd(c, ...)
    end,
  })
  wb.show_view(s.id, true)
  local running_inserts = inserts
  vim.fn.chansend(s.job, "exit 0\n")
  H.wait(5000, function()
    return s.status == "exited"
  end, "exited")
  inserts = 0
  wb.open({ focus = true })
  vim.wait(50)
  vim.cmd = cmd
  H.ok(running_inserts > 0, "Terminal mode requested while the tool runs")
  H.eq(inserts, 0, "no Terminal mode for an exited session")
  H.ok(api.nvim_buf_is_valid(s.buf), "the exited tool's output is still there")
  wb.hide()
  vim.env.PATH = path_before
end)

H.test("a missing executable doesn't break the editor; a clear error is returned", function()
  local profile = require("noctis.ai.profiles").get("missing")
  local s, err = sessions.start(profile, root, require("noctis.ai.workbench").prepare_window(), {})
  H.eq(s, nil)
  H.ok(err and err:find("not found", 1, true), err)
end)

-- ── Project without Git ──────────────────────────────────────────────────
H.suite("AI tracking: folder that isn't a Git repository")
H.test("baseline and change review work without Git", function()
  local plain = H.tmpdir("project without git")
  H.write(plain .. "/main.txt", "main\n")
  H.write(plain .. "/sub/file.txt", "sub\n")
  local pt = ensure(plain)
  H.eq(pt.interval.git, nil, "no git state")
  H.ok(pt.interval.files["main.txt"].hash)
  H.fake_batch(plain, "write main.txt main (AI)\\n", "write sub/new.txt new\\n", "delete sub/file.txt")
  wait_change(pt, "main.txt", "modified")
  wait_change(pt, "sub/new.txt", "added")
  wait_change(pt, "sub/file.txt", "deleted")
  -- Answer the confirmation dialog with "Revert"
  local confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 1
  end
  local ok = review.revert_file(pt, "sub/file.txt", "deleted")
  local ok2 = review.revert_file(pt, "main.txt", store.hash(H.read(plain .. "/main.txt")))
  vim.fn.confirm = confirm
  H.ok(ok, "the deleted file was recreated")
  H.eq(H.read(plain .. "/sub/file.txt"), "sub\n")
  H.ok(ok2, "the file was reverted")
  H.eq(H.read(plain .. "/main.txt"), "main\n")
  H.eq(H.read(plain .. "/sub/new.txt"), "new\n", "an unrelated new file is kept")
  wait_change(pt, "main.txt", nil)
  pt:stop()
end)

H.done()
