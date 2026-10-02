-- Safe mode, offline/plugin-less startup and missing-dependency behavior.
-- This file runs in an environment without plugins (an empty data directory).
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local R = require("noctis.registry")

H.suite(vim.env.NOCTIS_SAFE == "1" and "Safe mode" or "Startup without plugins (offline)")

H.test("startup makes no network requests and attempts no downloads", function()
  H.eq(vim.uv.fs_stat(vim.fn.stdpath("data") .. "/lazy/lazy.nvim"), nil, "lazy.nvim not downloaded")
  H.eq(package.loaded["lazy"], nil, "lazy not loaded")
end)

H.test("basic editing works (open/edit/save/undo)", function()
  local d = H.tmpdir("safe")
  local path = d .. "/a.txt"
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
  require("noctis.files").save()
  H.eq(H.read(path), "hello\n")
  vim.cmd("normal! ix")
  vim.cmd("undo")
  H.eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "hello")
end)

H.test("commands that need a plugin show as unavailable with a reason", function()
  local ok, reason = R.available("git.hunk_preview")
  H.eq(ok, false)
  H.ok(reason and (reason:find("safe mode", 1, true) or reason:find("setup", 1, true)), reason)
end)

H.test("the command palette opens with the plugin-less fallback", function()
  local called
  local orig = vim.ui.select
  vim.ui.select = function(items, opts, cb)
    called = #items
    cb(nil)
  end
  require("noctis.palette").open()
  vim.ui.select = orig
  H.ok(called and called > 50, "built-in selection list")
end)

H.test("theme, statusline and dashboard work without plugins", function()
  H.eq(vim.g.colors_name, "midnight-violet")
  H.ok(#require("noctis.ui.statusline").render() > 10)
end)

H.test("without ripgrep, search commands are disabled with a clear reason", function()
  local path = vim.env.PATH
  vim.env.PATH = "/nonexistent-dir"
  local ok, reason = R.available("files.grep")
  vim.env.PATH = path
  H.eq(ok, false)
  H.ok(reason:find("rg", 1, true), reason)
end)

H.test("without a language server, files open and edit normally", function()
  local d = H.tmpdir("nolsp")
  vim.env.PATH = "/usr/bin:/bin"
  vim.cmd("edit " .. vim.fn.fnameescape(d .. "/x.sh"))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo hi" })
  require("noctis.files").save()
  H.eq(H.read(d .. "/x.sh"), "echo hi\n")
  H.eq(#vim.lsp.get_clients({ bufnr = 0 }), 0)
end)

H.done()
