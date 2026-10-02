-- AI Workbench değişiklik takibi: deterministik testler (sahte CLI ile).
-- Kabul kriterleri 13–20'yi kapsar. Gerçek AI hizmetine bağlanılmaz.
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
    t[#t + 1] = ("%s satır %d"):format(prefix or "x", i)
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
  end, "başlangıç kaydı")
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

-- ── Git projesi ──────────────────────────────────────────────────────────
H.suite("AI takip: Git projesi (boşluk ve Türkçe karakterli yol)")
local root = H.tmpdir("proje ğüşiİöç")
H.init_repo(root)
H.write(root .. "/a.py", file_lines(20, "a"))
H.write(root .. "/b.txt", "b içerik\n")
H.write(root .. "/keep.txt", "korunacak\n")
H.write(root .. "/staged.txt", "eski\n")
H.write(root .. "/sub/c.py", "print('c')\n")
H.write(root .. "/crlf.txt", "bir\r\niki\r\nüç\r\n")
H.write(root .. "/.gitignore", "logs/\n")
H.write(root .. "/.env", "TOKEN=gizli\n")
H.write(root .. "/bin.dat", "PNG\0\1\2\3binary")
H.write(root .. "/big.bin", string.rep("Z", 1100 * 1024))
H.git(root, "add", "a.py", "b.txt", "keep.txt", "staged.txt", "sub/c.py", "crlf.txt", ".gitignore")
H.git(root, "commit", "-q", "-m", "ilk")
-- Başlangıçtan önce var olan kullanıcı değişiklikleri
H.write(root .. "/staged.txt", "staged yeni\n")
H.git(root, "add", "staged.txt")
H.write(root .. "/keep.txt", "korunacak (unstaged düzenleme)\n")
H.write(root .. "/untracked.txt", "izlenmeyen\n")
local index_before = H.read(root .. "/.git/index")
local status_before = H.git(root, "status", "--porcelain")
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()

local t
H.test("başlangıç kaydı alınır, Git index'i ve çalışma ağacı değişmez", function()
  local t0 = vim.uv.hrtime()
  t = ensure(root)
  H.note(("başlangıç kaydı: %d dosya, %.0f ms"):format(t.interval.stats.captured, (vim.uv.hrtime() - t0) / 1e6))
  H.eq(H.read(root .. "/.git/index"), index_before, "index baytları")
  H.eq(H.git(root, "status", "--porcelain"), status_before, "git status")
  H.eq(H.read(root .. "/staged.txt"), "staged yeni\n")
end)

H.test("önceden var olan staged/unstaged/untracked içerik başlangıca dahil, yeni değişiklik sayılmaz", function()
  local f = t.interval.files
  H.ok(f["staged.txt"] and f["staged.txt"].hash, "staged.txt kayıtlı")
  H.ok(f["keep.txt"] and f["keep.txt"].hash, "keep.txt kayıtlı")
  H.ok(f["untracked.txt"] and f["untracked.txt"].hash, "untracked.txt kayıtlı")
  H.eq(store.get_blob(root, f["keep.txt"].hash), "korunacak (unstaged düzenleme)\n", "disk içeriği saklandı (hash değil)")
  H.eq(vim.tbl_count(t.changes), 0, "başlangıçta değişiklik yok")
  H.ok(#(t.interval.git.entries or {}) >= 3, "git durumu kaydedildi")
end)

H.test("kapsam: hassas, büyük ve binary dosyalar doğru sınıflandırılır", function()
  local f = t.interval.files
  H.eq(f[".env"] and f[".env"].reason, "sensitive", ".env")
  H.eq(f[".env"].hash, nil, ".env içeriği kopyalanmadı")
  H.eq(f["big.bin"] and f["big.bin"].reason, "large", "big.bin")
  H.ok(f["bin.dat"] and f["bin.dat"].binary, "bin.dat binary")
  H.eq(f["logs/x"], nil)
end)

H.test("normal yazma ~1 sn içinde görünür; satır sayıları doğru", function()
  local new = file_lines(20, "a"):gsub("a satır 3\n", "a satır 3 AI\n")
  local t_written = H.fake_batch(root, "write a.py " .. new:gsub("\n", "\\n"))
  wait_change(t, "a.py", "modified")
  local ms = (vim.uv.hrtime() - t_written) / 1e6
  H.note(("yazmadan görünür güncellemeye: %.0f ms"):format(ms))
  H.ok(ms < 1500, "gecikme < 1500 ms")
  H.eq(t.changes["a.py"].adds, 1)
  H.eq(t.changes["a.py"].dels, 1)
end)

H.test("atomic save (geçici dosya + rename): tek değişiklik, geçici dosya listede kalmaz", function()
  H.fake_batch(root, "atomic b.txt b yeni\\n")
  wait_change(t, "b.txt", "modified")
  vim.wait(600)
  for rel in pairs(t.changes) do
    H.ok(not rel:find("%.tmp"), "geçici dosya listede: " .. rel)
  end
end)

H.test("dosya oluşturma, silme ve yeni alt klasör izlenir", function()
  H.fake_batch(root, "write new.py print(1)\\n", "delete keep.txt", "write yeni/derin/x.py x = 1\\n")
  wait_change(t, "new.py", "added")
  wait_change(t, "keep.txt", "deleted")
  wait_change(t, "yeni/derin/x.py", "added")
  -- yeni klasör altında sonraki yazmalar da izlenir
  H.fake_batch(root, "write yeni/derin/y.py y = 2\\n")
  wait_change(t, "yeni/derin/y.py", "added")
end)

H.test(".gitignore ile dışlanan yollar listeye girmez", function()
  H.fake_batch(root, "write logs/out.log günlük\\n", "write z_marker.txt işaret\\n")
  wait_change(t, "z_marker.txt", "added")
  vim.wait(400)
  H.eq(t.changes["logs/out.log"], nil)
end)

H.test("hassas dosya değişikliği bildirilir ama içerik/diff yoktur", function()
  H.fake_batch(root, "write .env TOKEN=yeni\\n")
  wait_change(t, ".env", "modified")
  H.eq(t.changes[".env"].no_baseline, "sensitive")
end)

H.test("temiz buffer diskteki kararlı içerikle yeniden yüklenir, imleç korunur", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/sub/c.py"))
  local buf = api.nvim_get_current_buf()
  H.fake_batch(root, "write sub/c.py print('c')\\nprint('AI')\\n")
  H.wait(5000, function()
    return api.nvim_buf_get_lines(buf, 0, -1, false)[2] == "print('AI')"
  end, "buffer yeniden yüklendi")
  H.eq(vim.bo[buf].modified, false)
  H.eq(vim.b[buf].noctis_conflict, nil)
end)

H.test("kaydedilmemiş buffer otomatik yüklenmez/kaydedilmez; çatışma işaretlenir; iki içerik korunur", function()
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/crlf.txt"))
  local buf = api.nvim_get_current_buf()
  H.eq(vim.bo[buf].fileformat, "dos", "CRLF algılandı")
  api.nvim_buf_set_lines(buf, 0, 1, false, { "bir (yerel düzenleme)" })
  H.ok(vim.bo[buf].modified)
  H.fake_batch(root, "write crlf.txt bir\\r\\niki\\r\\nüç (AI)\\r\\n")
  wait_change(t, "crlf.txt", "modified")
  H.wait(3000, function()
    return vim.b[buf].noctis_conflict ~= nil
  end, "çatışma işareti")
  H.eq(api.nvim_buf_get_lines(buf, 0, 1, false)[1], "bir (yerel düzenleme)", "yerel düzenleme korundu")
  H.eq(H.read(root .. "/crlf.txt"), "bir\r\niki\r\nüç (AI)\r\n", "disk içeriği ezilmedi")
  H.ok(require("noctis.sync").disk_changed(buf), "kaydetmede disk yeniden denetlenir")
end)

H.test("çatışmada 3 yollu birleştirme iki tarafı da korur (taban: son senkron)", function()
  local buf = vim.fn.bufnr(root .. "/crlf.txt")
  require("noctis.sync").merge(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  H.eq(lines[1], "bir (yerel düzenleme)")
  H.eq(lines[3], "üç (AI)")
  H.eq(vim.b[buf].noctis_conflict, nil, "temiz birleştirmede çatışma kalktı")
  vim.api.nvim_buf_call(buf, function()
    require("noctis.files").save(buf)
  end)
  H.eq(vim.bo[buf].modified, false, "kaydedildi (soru sorulmadan)")
  H.eq(H.read(root .. "/crlf.txt"), "bir (yerel düzenleme)\r\niki\r\nüç (AI)\r\n", "CRLF korunarak kaydedildi")
end)

H.test("seçili hunk geri alma yalnız o hunk'ı değiştirir; index korunur", function()
  local base = file_lines(30, "h")
  H.write(root .. "/h.py", base)
  -- h.py başlangıçta yoktu; onu başlangıca almak için yeni aralık başlat
  local done
  tracker.new_interval(root, function(nt)
    done = nt
  end)
  H.wait(20000, function()
    return done ~= nil
  end, "yeni aralık")
  t = done
  local idx = H.read(root .. "/.git/index")
  local cur = base:gsub("h satır 3\n", "h satır 3 AI\n"):gsub("h satır 25\n", "h satır 25 AI\n")
  H.fake_batch(root, "write h.py " .. cur:gsub("\n", "\\n"))
  wait_change(t, "h.py", "modified")
  local disk = H.read(root .. "/h.py")
  local hk = hunks.diff(base, disk)
  H.eq(#hk, 2, "iki hunk")
  local ok = review.revert_hunk(t, "h.py", store.hash(disk), hk[2])
  H.ok(ok, "geri alındı")
  local after = H.read(root .. "/h.py")
  H.ok(after:find("h satır 3 AI", 1, true), "ilk hunk korunuyor")
  H.ok(not after:find("h satır 25 AI", 1, true), "ikinci hunk geri alındı")
  H.eq(H.read(root .. "/.git/index"), idx, "index değişmedi")
end)

H.test("incelemeden sonra dosya değişirse geri alma körlemesine yapılmaz", function()
  local viewed = store.hash(H.read(root .. "/h.py"))
  H.fake_batch(root, "append h.py son satır (ikinci AI yazması)\\n")
  vim.wait(50)
  local before = H.read(root .. "/h.py")
  local ok = review.revert_file(t, "h.py", viewed)
  H.eq(ok, false, "reddedildi")
  H.eq(H.read(root .. "/h.py"), before, "disk değişmedi")
end)

H.test("kaydedilmemiş buffer varken geri alma reddedilir", function()
  wait_change(t, "h.py", "modified")
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/h.py"))
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, 1, false, { "kullanıcı düzenlemesi" })
  local disk = H.read(root .. "/h.py")
  local ok = review.revert_file(t, "h.py", store.hash(disk))
  H.eq(ok, false)
  H.eq(H.read(root .. "/h.py"), disk)
  vim.cmd("edit!")
end)

H.test("önceki içeriği olmayan (kapsam dışı) dosyada geri alma yapılmaz ve gerekçe söylenir", function()
  H.fake_batch(root, "append big.bin EK")
  wait_change(t, "big.bin", "modified")
  H.eq(t.changes["big.bin"].no_baseline, "large")
  local disk = H.read(root .. "/big.bin")
  H.eq(review.revert_file(t, "big.bin", store.hash(disk)), false)
  H.eq(H.read(root .. "/big.bin"), disk)
end)

H.test("incelendi işareti içerik yeniden değişince geçersizleşir", function()
  H.fake_batch(root, "write r.py r = 1\\n")
  wait_change(t, "r.py", "added")
  t:mark_reviewed("r.py", true)
  H.ok(t:is_reviewed("r.py"))
  H.fake_batch(root, "write r.py r = 2\\n")
  H.wait(5000, function()
    return not t:is_reviewed("r.py")
  end, "işaret geçersiz")
end)

H.test("değişiklik listesi kaynağı belirli bir araca atamaz; iki karşılaştırma ayrı etiketlenir", function()
  review.set_root(root)
  local buf = review.ensure_list_buf()
  review.mode = "interval"
  review.render()
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(text:find("hangi programın yazdığı doğrulanmaz", 1, true), "kaynak uyarısı")
  H.ok(not text:find("Claude", 1, true) and not text:find("Codex", 1, true), "araç adı atanmadı")
  review.mode = "git"
  review.render()
  local gtext = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  H.ok(gtext:find("Git değişiklikleri (HEAD'e göre)", 1, true), "Git görünümü ayrı")
  review.mode = "interval"
end)

H.test("yeni aralık dosyaları değiştirmez, değişiklik listesini sıfırlar", function()
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

-- ── PTY oturumu (sahte CLI) ──────────────────────────────────────────────
H.suite("AI oturumu: gerçek PTY + sahte CLI")
require("noctis.config").options.ai.profiles.fake = { label = "Sahte AI", cmd = { H.fake } }
require("noctis.config").options.ai.profiles.missing = { label = "Eksik Araç", cmd = { "noctis-olmayan-arac-xyz" } }
local sessions = require("noctis.ai.sessions")

H.test("oturum proje kökünde başlar, çıktı kanıtıyla 'çalışıyor' olur, dosya yazması izlenir", function()
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
  H.ok(banner:find(vim.fn.fnamemodify(root, ":t"), 1, true), "cwd proje kökü")
  vim.fn.chansend(s.job, "write pty.txt merhaba\n")
  wait_change(t, "pty.txt", "added")
  -- Panel gizlenince süreç devam eder
  require("noctis.ai.workbench").hide()
  vim.fn.chansend(s.job, "write pty2.txt gizliyken\n")
  wait_change(t, "pty2.txt", "added")
  H.ok(sessions.alive(s), "süreç yaşıyor")
  vim.fn.chansend(s.job, "exit 3\n")
  H.wait(5000, function()
    return s.status == "exited"
  end, "exited")
  H.eq(s.code, 3)
  H.eq(sessions.status_text(s), "çıktı (3)")
end)

H.test("eksik executable editörü bozmaz; anlaşılır hata döner", function()
  local profile = require("noctis.ai.profiles").get("missing")
  local s, err = sessions.start(profile, root, require("noctis.ai.workbench").prepare_window(), {})
  H.eq(s, nil)
  H.ok(err and err:find("bulunamadı", 1, true), err)
end)

-- ── Git olmayan proje ────────────────────────────────────────────────────
H.suite("AI takip: Git deposu olmayan klasör")
H.test("başlangıç kaydı ve değişiklik inceleme Git olmadan çalışır", function()
  local plain = H.tmpdir("gitsiz proje")
  H.write(plain .. "/main.txt", "ana\n")
  H.write(plain .. "/alt/dosya.txt", "alt\n")
  local pt = ensure(plain)
  H.eq(pt.interval.git, nil, "git durumu yok")
  H.ok(pt.interval.files["main.txt"].hash)
  H.fake_batch(plain, "write main.txt ana (AI)\\n", "write alt/yeni.txt yeni\\n", "delete alt/dosya.txt")
  wait_change(pt, "main.txt", "modified")
  wait_change(pt, "alt/yeni.txt", "added")
  wait_change(pt, "alt/dosya.txt", "deleted")
  -- Onay diyaloğunu "Geri al" ile yanıtla
  local confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 1
  end
  local ok = review.revert_file(pt, "alt/dosya.txt", "deleted")
  local ok2 = review.revert_file(pt, "main.txt", store.hash(H.read(plain .. "/main.txt")))
  vim.fn.confirm = confirm
  H.ok(ok, "silinen dosya yeniden oluşturuldu")
  H.eq(H.read(plain .. "/alt/dosya.txt"), "alt\n")
  H.ok(ok2, "dosya geri alındı")
  H.eq(H.read(plain .. "/main.txt"), "ana\n")
  H.eq(H.read(plain .. "/alt/yeni.txt"), "yeni\n", "ilgisiz yeni dosya korunur")
  wait_change(pt, "main.txt", nil)
  pt:stop()
end)

H.done()
