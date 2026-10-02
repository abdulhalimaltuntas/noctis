-- LSP flows and formatting with a real language server (Python: pyright).
-- Plugins must be installed (noctis --setup) and pyright-langserver must be on PATH.
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api

H.suite("LSP: Python (pyright)")
if vim.fn.executable("pyright-langserver") == 0 then
  H.note("no pyright-langserver; LSP tests skipped")
  H.done()
end

local root = H.tmpdir("lsp project")
H.write(root .. "/pyproject.toml", "[project]\nname='t'\n")
H.write(root .. "/main.py", 'def greet(name):\n    return "hi " + name\n\n\nprint(greet("x"))\nundefined_var\n')
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()
vim.cmd("edit main.py")
local buf = api.nvim_get_current_buf()

local client
H.test("pyright attaches to the buffer (lazy-loaded lspconfig + vim.lsp.enable)", function()
  H.wait(20000, function()
    client = vim.lsp.get_clients({ bufnr = buf, name = "pyright" })[1]
    return client ~= nil and client.initialized
  end, "pyright attached")
end)

H.test("diagnostics come from the real server", function()
  -- pyright's first (cold) analysis can take over 15 s under load
  H.wait(45000, function()
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      if d.message:find("undefined_var", 1, true) then
        return true
      end
    end
  end, "undefined_var diagnostic")
end)

H.test("go to definition returns the right line", function()
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.position = { line = 4, character = 7 }
  local res = client:request_sync("textDocument/definition", params, 10000, buf)
  H.ok(res and res.result, "response")
  local loc = res.result[1] or res.result
  local range = loc.range or loc.targetSelectionRange
  H.eq(range.start.line, 0, "the def greet line")
end)

H.test("completion includes the server's suggestion (gre → greet)", function()
  api.nvim_buf_set_lines(buf, 6, 6, false, { "gre" })
  vim.wait(300)
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.position = { line = 6, character = 3 }
  local res = client:request_sync("textDocument/completion", params, 10000, buf)
  local items = res and res.result and (res.result.items or res.result) or {}
  local found = false
  for _, it in ipairs(items) do
    if it.label == "greet" then
      found = true
    end
  end
  H.ok(found, "greet suggested")
  api.nvim_buf_set_lines(buf, 6, 7, false, {})
end)

H.test("rename changes every reference (in the buffer, unsaved)", function()
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.position = { line = 0, character = 5 }
  params.newName = "salute"
  local res = client:request_sync("textDocument/rename", params, 10000, buf)
  H.ok(res and res.result, "rename response")
  vim.lsp.util.apply_workspace_edit(res.result, client.offset_encoding)
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(text:find("def salute%(") and text:find("print%(salute%("), text)
end)

H.test("blink.cmp loads and provides LSP capabilities", function()
  local ok, blink = pcall(require, "blink.cmp")
  H.ok(ok, tostring(blink))
  H.ok(blink.get_lsp_capabilities().textDocument.completion ~= nil)
end)

H.suite("Formatting (conform + ruff)")
H.test("the Space c f equivalent formats the file; format-on-save is off by default", function()
  if vim.fn.executable("ruff") == 0 then
    H.note("no ruff; skipped")
    return
  end
  local path = root .. "/fmt.py"
  H.write(path, "x=[1,2,\n 3]\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local b = api.nvim_get_current_buf()
  -- Format-on-save is off: the content must stay the same
  api.nvim_buf_set_lines(b, 0, -1, false, { "y=1" })
  vim.cmd("write")
  H.eq(H.read(path), "y=1\n", "format-on-save off")
  api.nvim_buf_set_lines(b, 0, -1, false, { "x=[1,2,", " 3]" })
  local done, err
  require("conform").format({ bufnr = b, async = true, lsp_format = "fallback" }, function(e)
    err, done = e, true
  end)
  H.wait(10000, function()
    return done
  end, "format")
  H.eq(err, nil)
  H.eq(api.nvim_buf_get_lines(b, 0, -1, false)[1], "x = [1, 2, 3]")
end)

H.test("format_on_save runs on save once enabled for the filetype", function()
  if vim.fn.executable("ruff") == 0 then
    return
  end
  require("noctis.format").session_ft.python = true
  local path = root .. "/fmt2.py"
  H.write(path, "")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  api.nvim_buf_set_lines(0, 0, -1, false, { "a=( 1 )" })
  vim.cmd("write")
  H.eq(H.read(path), "a = 1\n")
  require("noctis.format").session_ft.python = nil
end)

H.suite("Syntax")
H.test("Tree-sitter is active when a parser exists, otherwise the Vim syntax fallback", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/main.py"))
  local has_ts = require("noctis.lang").has_parser("python")
  if has_ts then
    H.ok(vim.treesitter.highlighter.active[api.nvim_get_current_buf()] ~= nil, "Tree-sitter active")
    H.note("python parser installed: Tree-sitter highlighting active")
  else
    H.eq(vim.bo.syntax, "python", "Vim regex syntax")
    H.note("no python parser: using the Vim syntax fallback")
  end
end)

H.done()
