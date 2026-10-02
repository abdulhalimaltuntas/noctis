-- Çekirdek davranış testleri: yapılandırma, kısayollar, veri güvenliği.
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api

-- ── Yapılandırma ─────────────────────────────────────────────────────────
H.suite("Yapılandırma doğrulama")
local cfg = require("noctis.config")

H.test("geçersiz değerler açıklamalı hata üretir ve varsayılan kullanılır", function()
  local errors, warnings = {}, {}
  local out = cfg.validate({
    theme = "pembe",
    icons = "evet",
    ui = { explorer_width = 500, wrap = true },
    format_on_save = { enabled = true, filetypes = { "lua" } },
    temaa = "glacier",
    ai = { width = 2, layout = "right" },
  }, cfg.defaults, nil, errors, warnings)
  H.eq(out.theme, "midnight-violet", "geçersiz tema → varsayılan")
  H.eq(out.icons, true, "yanlış tip → varsayılan")
  H.eq(out.ui.explorer_width, 30, "aralık dışı → varsayılan")
  H.eq(out.ui.wrap, true, "geçerli alt alan korunur")
  H.eq(out.format_on_save.filetypes[1], "lua")
  H.eq(out.ai.layout, "right")
  H.eq(out.ai.width, 0.42)
  H.eq(#errors, 4, "hata sayısı: " .. vim.inspect(errors))
  H.eq(#warnings, 1, "bilinmeyen anahtar uyarısı")
  H.ok(warnings[1]:find("temaa", 1, true))
end)

H.test("sözdizimi hatalı config.lua editörü bozmaz; hata görünür", function()
  local path = cfg.path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  H.write(path, "return { theme = ")
  cfg.load()
  H.ok(#cfg.errors == 1 and cfg.errors[1]:find("okunamadı", 1, true), vim.inspect(cfg.errors))
  H.eq(cfg.options.theme, "midnight-violet")
  H.write(path, "return { theme = 'amber' }")
  cfg.load()
  H.eq(cfg.options.theme, "amber")
  os.remove(path)
  cfg.load()
end)

-- ── Komut kaydı ve kısayollar ────────────────────────────────────────────
H.suite("Komut kaydı ve kısayollar")
local R = require("noctis.registry")

H.test("varsayılan kısayollarda çakışma veya önek sorunu yok", function()
  local p = R.conflicts()
  H.eq(#p, 0, table.concat(p, "\n"))
end)

H.test("şartnamedeki kısayol sözleşmesi uygulanmış", function()
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
    H.ok(m and m.desc == R.by_id[id].title, "eşleme uygulanmadı: " .. keys)
  end
end)

H.test("her komutun kullanılabilirlik denetimi hata fırlatmaz", function()
  for _, c in ipairs(R.list) do
    local ok, reason = R.available(c)
    H.ok(ok == true or (ok == false and type(reason) == "string"), c.id)
  end
end)

H.test("temel Vim tuşları yeniden eşlenmedi (i, u, /, n, dd, :)", function()
  -- Yalnız global eşlemeler (dashboard gibi özel buffer'ların yerel tuşları hariç)
  local global = {}
  for _, m in ipairs(api.nvim_get_keymap("n")) do
    global[m.lhs] = true
  end
  for _, k in ipairs({ "i", "u", "/", "n", "dd", ":", "v", "p", "y", "x", "o" }) do
    H.eq(global[k], nil, "Normal mod " .. k)
  end
  H.eq(vim.fn.maparg("<Esc>", "t"), "", "terminalde Esc uygulamaya gider")
  H.eq(vim.fn.maparg("<C-c>", "t"), "", "terminalde Ctrl-C uygulamaya gider")
  H.ok(vim.fn.maparg("<C-\\>e", "t") ~= "", "terminalden editöre dönüş eşlemesi var")
  H.eq(vim.fn.maparg(" ", "i"), "", "Insert modda boşluk değişmedi")
end)

H.test("kullanıcı kısayol override'ı ve devre dışı bırakma", function()
  cfg.options.keymaps = { ["files.grep"] = "<leader>/", ["ui.focus"] = false }
  H.eq(R.effective_keys(R.by_id["files.grep"]), "<leader>/")
  H.eq(R.effective_keys(R.by_id["ui.focus"]), false)
  cfg.options.keymaps = {}
end)

H.test("docs/KEYMAPS.md komut kaydıyla güncel", function()
  local doc = H.read(H.repo .. "/docs/KEYMAPS.md")
  H.ok(doc, "docs/KEYMAPS.md yok (tests/gen-keymaps.sh)")
  H.eq(doc, R.markdown() .. "\n", "KEYMAPS.md eski; tests/gen-keymaps.sh çalıştırın")
end)

-- ── Dosya ve veri güvenliği ──────────────────────────────────────────────
H.suite("Dosya düzenleme ve veri güvenliği")
local dir = H.tmpdir("çekirdek test ğüş")
vim.cmd("cd " .. vim.fn.fnameescape(dir))
require("noctis.project").refresh()

H.test("boşluklu/Türkçe yolda UTF-8 içerik bozulmadan kaydedilir", function()
  local path = dir .. "/klasör adı/dosya ğüşiİöç.txt"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  api.nvim_buf_set_lines(0, 0, -1, false, { "ğüşiİöç ĞÜŞIİÖÇ", "ikinci satır" })
  require("noctis.files").save()
  H.eq(H.read(path), "ğüşiİöç ĞÜŞIİÖÇ\nikinci satır\n")
  vim.cmd("bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.eq(api.nvim_buf_get_lines(0, 0, 1, false)[1], "ğüşiİöç ĞÜŞIİÖÇ")
  vim.cmd("bwipeout!")
end)

H.test("CRLF dosyası gereksiz dönüştürülmez; son satır biçimi korunur", function()
  local path = dir .. "/win.txt"
  H.write(path, "a\r\nb\r\nc")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.eq(vim.bo.fileformat, "dos")
  api.nvim_buf_set_lines(0, 1, 2, false, { "B" })
  require("noctis.files").save()
  H.eq(H.read(path), "a\r\nB\r\nc", "CRLF ve eksik son satır sonu korundu")
  vim.cmd("bwipeout!")
end)

H.test("kaydedilmemiş buffer'ı kapatırken iptal edilince içerik korunur", function()
  local path = dir .. "/korunan.txt"
  H.write(path, "orijinal\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "kaydedilmemiş" })
  local confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 3 -- İptal
  end
  require("noctis.buffers").delete(buf)
  vim.fn.confirm = confirm
  H.ok(api.nvim_buf_is_valid(buf), "buffer açık kaldı")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "kaydedilmemiş")
  H.eq(H.read(path), "orijinal\n", "disk değişmedi")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("güvenli çıkış kaydedilmemiş dosyaları listeler ve iptalde çıkmaz", function()
  local path = dir .. "/cikis.txt"
  H.write(path, "x\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  api.nvim_buf_set_lines(0, 0, -1, false, { "y" })
  local seen
  local confirm = vim.fn.confirm
  vim.fn.confirm = function(msg)
    seen = msg
    return 3 -- İptal
  end
  require("noctis.quit").quit()
  vim.fn.confirm = confirm
  H.ok(seen and seen:find("cikis.txt", 1, true), "dosya listelendi: " .. tostring(seen))
  vim.bo.modified = false
  vim.cmd("bwipeout!")
end)

H.test("dışarıdan değişen dosyada kaydetme çatışma akışına yönlenir (sessiz ezme yok)", function()
  local path = dir .. "/dis.txt"
  H.write(path, "bir\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "yerel" })
  vim.wait(20)
  H.write(path, "dış program\n")
  local resolved = false
  local orig = require("noctis.sync").resolve
  require("noctis.sync").resolve = function()
    resolved = true
  end
  require("noctis.files").save(buf)
  require("noctis.sync").resolve = orig
  H.ok(resolved, "çatışma çözümü çağrıldı")
  H.eq(H.read(path), "dış program\n", "disk ezilmedi")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("silinen dosyanın açık buffer içeriği kaybolmaz", function()
  local path = dir .. "/silinecek.txt"
  H.write(path, "önemli içerik\n")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = api.nvim_get_current_buf()
  os.remove(path)
  require("noctis.sync").check(buf)
  H.wait(2000, function()
    return vim.bo[buf].modified and vim.b[buf].noctis_conflict ~= nil
  end, "silinme işaretlendi")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "önemli içerik")
  vim.bo[buf].modified = false
  vim.cmd("bwipeout!")
end)

H.test("geri alınabilir silme: dosya çöp kutusuna taşınır ve geri yüklenir", function()
  local path = dir .. "/cop.txt"
  H.write(path, "geri gelecek\n")
  local ok = require("noctis.trash").move(path)
  H.ok(ok)
  H.eq(H.read(path), nil)
  local items = require("noctis.trash").list()
  H.eq(items[1].path, path)
  H.ok(require("noctis.trash").restore(items[1]))
  H.eq(H.read(path), "geri gelecek\n")
end)

H.test("büyük dosya modu: ağır özellikler kapanır, dosya düzenlenebilir kalır", function()
  local path = dir .. "/buyuk.py"
  H.write(path, string.rep("x = 1\n", 60000))
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  H.ok(vim.b.noctis_bigfile, "bigfile işareti")
  vim.wait(100)
  H.eq(vim.bo.syntax, "")
  H.ok(vim.bo.modifiable, "düzenlenebilir")
  vim.cmd("bwipeout!")
end)

-- ── Toplu değiştirme ─────────────────────────────────────────────────────
H.suite("Projede bul ve değiştir")
local replace = require("noctis.replace")

H.test("önizleme kapsamı doğru; uygulama CRLF ve diğer satırları korur", function()
  local r = H.tmpdir("degistir")
  H.write(r .. "/a.py", "foo = 1\nbar = foo\n")
  H.write(r .. "/b.txt", "foo\r\nkalan\r\n")
  H.write(r .. "/c.txt", "ilgisiz\n")
  local changes = assert(replace.collect({ pattern = "foo", replacement = "baz", regex = false }, r))
  H.eq(#changes, 3, "3 satır")
  changes[2].on = false -- ikinci değişikliği hariç tut (a.py satır 2)
  replace.apply(changes)
  H.eq(H.read(r .. "/a.py"), "baz = 1\nbar = foo\n")
  H.eq(H.read(r .. "/b.txt"), "baz\r\nkalan\r\n")
  H.eq(H.read(r .. "/c.txt"), "ilgisiz\n")
end)

H.test("önizlemeden sonra değişen satır uygulamada atlanır", function()
  local r = H.tmpdir("degistir2")
  H.write(r .. "/a.txt", "foo\nfoo\n")
  local changes = assert(replace.collect({ pattern = "foo", replacement = "bar", regex = false }, r))
  H.write(r .. "/a.txt", "foo\nbaşka biri değiştirdi\n")
  replace.apply(changes)
  H.eq(H.read(r .. "/a.txt"), "bar\nbaşka biri değiştirdi\n")
end)

H.test("regex modu ripgrep grup sözdizimiyle önizleme = uygulama", function()
  local r = H.tmpdir("degistir3")
  H.write(r .. "/a.js", "getUser(1)\ngetItem(2)\n")
  local changes = assert(replace.collect({ pattern = [[get(\w+)\(]], replacement = "fetch$1(", regex = true }, r))
  H.eq(changes[1].new, "fetchUser(1)")
  replace.apply(changes)
  H.eq(H.read(r .. "/a.js"), "fetchUser(1)\nfetchItem(2)\n")
end)

-- ── Hunk aritmetiği ──────────────────────────────────────────────────────
H.suite("Hunk geri alma kesinliği")
local hunks = require("noctis.ai.hunks")
H.test("ekleme/silme/son satır newline farkı bayt düzeyinde geri alınır", function()
  local cases = {
    { "a\nb\nc\n", "a\nX\nb\nc\n" },
    { "a\nb\nc\n", "a\nc\n" },
    { "a\nb\n", "X\na\nb\n" },
    { "a\nb\n", "a\nb\nZ\n" },
    { "a\nb", "a\nb\n" },
    { "a\r\nb\r\n", "a\r\nB\r\n" },
    { "", "yeni\n" },
  }
  for i, c in ipairs(cases) do
    local base, cur = c[1], c[2]
    local hk = hunks.diff(base, cur)
    local text = cur
    for j = #hk, 1, -1 do
      text = hunks.revert_hunk(base, text, hunks.diff(base, text)[j] or hk[j])
    end
    H.eq(text, base, "durum " .. i)
  end
end)

-- ── Oturum ve terminal ───────────────────────────────────────────────────
H.suite("Oturum ve terminal")
H.test("oturum kaydı ve geri yükleme kaydedilmemiş buffer'ın üzerine yazmaz", function()
  local r = H.tmpdir("oturum")
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
  api.nvim_buf_set_lines(0, 0, -1, false, { "kaydedilmemiş x" })
  require("noctis.session").restore()
  H.eq(#api.nvim_tabpage_list_wins(0), 2, "bölme düzeni geri geldi")
  local xb = vim.fn.bufnr(r .. "/x.txt")
  H.eq(api.nvim_buf_get_lines(xb, 0, 1, false)[1], "kaydedilmemiş x", "değiştirilmiş buffer korundu")
  vim.bo[xb].modified = false
end)

H.test("terminal paneli gizlenince süreç ve çıktı korunur", function()
  local term = require("noctis.terminal")
  local t = term.new({ cmd = { "sh", "-c", "echo NOCTIS_TERM_OK; exec sleep 30" } })
  H.wait(3000, function()
    return table.concat(api.nvim_buf_get_lines(t.buf, 0, -1, false), "\n"):find("NOCTIS_TERM_OK", 1, true) ~= nil
  end, "çıktı")
  term.hide()
  H.ok(not term.is_visible())
  H.ok(vim.fn.jobpid(t.job) > 0, "süreç yaşıyor")
  term.show()
  H.eq(api.nvim_win_get_buf(term.win), t.buf, "aynı oturuma dönüldü")
  H.ok(table.concat(api.nvim_buf_get_lines(t.buf, 0, -1, false), "\n"):find("NOCTIS_TERM_OK", 1, true), "çıktı korundu")
  H.ok(#require("noctis.quit").running() >= 1, "çıkış özeti çalışan terminali görür")
  vim.fn.jobstop(t.job)
  term.hide()
end)

H.test("terminal alt süreci NOCTIS'e özgü ortamı devralmaz", function()
  local env = require("noctis.util").child_env()
  H.eq(env.NOCTIS_HOME, nil)
  H.eq(env.NVIM_APPNAME, vim.env.NOCTIS_ORIG_NVIM_APPNAME)
end)

H.test("görev algılama projeden komut üretir ama hiçbir şey çalıştırmaz", function()
  local r = H.tmpdir("gorev")
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

H.done()
