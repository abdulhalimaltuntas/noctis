-- Gerçek dil sunucusuyla (Python: pyright) LSP akışları ve biçimlendirme.
-- Eklentiler kurulu olmalı (noctis --setup) ve pyright-langserver PATH'te olmalı.
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api

H.suite("LSP: Python (pyright)")
if vim.fn.executable("pyright-langserver") == 0 then
  H.note("pyright-langserver yok; LSP testleri atlandı")
  H.done()
end

local root = H.tmpdir("lsp proje")
H.write(root .. "/pyproject.toml", "[project]\nname='t'\n")
H.write(root .. "/main.py", 'def greet(name):\n    return "hi " + name\n\n\nprint(greet("x"))\nundefined_var\n')
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()
vim.cmd("edit main.py")
local buf = api.nvim_get_current_buf()

local client
H.test("pyright buffer'a bağlanır (lazy yüklenen lspconfig + vim.lsp.enable)", function()
  H.wait(20000, function()
    client = vim.lsp.get_clients({ bufnr = buf, name = "pyright" })[1]
    return client ~= nil and client.initialized
  end, "pyright bağlantısı")
end)

H.test("diagnostics gerçek sunucudan gelir", function()
  -- pyright'ın ilk (soğuk) analizi yük altında 15 sn'yi aşabiliyor
  H.wait(45000, function()
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      if d.message:find("undefined_var", 1, true) then
        return true
      end
    end
  end, "undefined_var tanılaması")
end)

H.test("tanıma git doğru satırı döndürür", function()
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.position = { line = 4, character = 7 }
  local res = client:request_sync("textDocument/definition", params, 10000, buf)
  H.ok(res and res.result, "yanıt")
  local loc = res.result[1] or res.result
  local range = loc.range or loc.targetSelectionRange
  H.eq(range.start.line, 0, "def greet satırı")
end)

H.test("completion sunucu önerisi içerir (gre → greet)", function()
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
  H.ok(found, "greet önerildi")
  api.nvim_buf_set_lines(buf, 6, 7, false, {})
end)

H.test("rename tüm referansları değiştirir (buffer'da, kaydedilmeden)", function()
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.position = { line = 0, character = 5 }
  params.newName = "selam"
  local res = client:request_sync("textDocument/rename", params, 10000, buf)
  H.ok(res and res.result, "rename yanıtı")
  vim.lsp.util.apply_workspace_edit(res.result, client.offset_encoding)
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(text:find("def selam%(") and text:find("print%(selam%("), text)
end)

H.test("blink.cmp yüklenir ve LSP yeteneklerini sağlar", function()
  local ok, blink = pcall(require, "blink.cmp")
  H.ok(ok, tostring(blink))
  H.ok(blink.get_lsp_capabilities().textDocument.completion ~= nil)
end)

H.suite("Biçimlendirme (conform + ruff)")
H.test("Space c f eşdeğeri dosyayı biçimlendirir; kaydederken varsayılan kapalı", function()
  if vim.fn.executable("ruff") == 0 then
    H.note("ruff yok; atlandı")
    return
  end
  local path = root .. "/fmt.py"
  H.write(path, "x=[1,2,\n 3]\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local b = api.nvim_get_current_buf()
  -- Kaydetmede biçimlendirme kapalı: içerik aynı kalmalı
  api.nvim_buf_set_lines(b, 0, -1, false, { "y=1" })
  vim.cmd("write")
  H.eq(H.read(path), "y=1\n", "format-on-save kapalı")
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

H.test("format_on_save dosya türüne göre açılınca kayıtta çalışır", function()
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

H.suite("Söz dizimi")
H.test("Tree-sitter parser'ı yokken Vim söz dizimi çalışır", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/main.py"))
  local has_ts = require("noctis.lang").has_parser("python")
  if has_ts then
    H.ok(vim.treesitter.highlighter.active[api.nvim_get_current_buf()] ~= nil, "Tree-sitter etkin")
    H.note("python parser kurulu: Tree-sitter vurgulama etkin")
  else
    H.eq(vim.bo.syntax, "python", "Vim regex söz dizimi")
    H.note("python parser yok: Vim söz dizimi yedeği kullanılıyor")
  end
end)

H.done()
