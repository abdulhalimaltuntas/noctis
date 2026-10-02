-- NOCTIS komut tanımları (tek kaynak). Her komut palette görünür; kısayolu
-- olanlar Normal mod eşlemesi olarak uygulanır ve which-key'de listelenir.
local R = require("noctis.registry")
local U = require("noctis.util")

local function plugin(name)
  return function()
    if U.is_safe_mode() then
      return false, "güvenli modda eklentiler kapalı"
    end
    local ok, cfg = pcall(require, "lazy.core.config")
    if not ok then
      return false, "eklentiler kurulu değil (noctis --setup)"
    end
    local p = cfg.plugins[name]
    if not p or not vim.uv.fs_stat(p.dir) then
      return false, name .. " kurulu değil (noctis --setup)"
    end
    return true
  end
end

local function exe(name, hint)
  return function()
    if U.has(name) then
      return true
    end
    return false, ("`%s` bulunamadı%s"):format(name, hint and (" — " .. hint) or "")
  end
end

local function lsp_attached()
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    return true
  end
  return false, "bu buffer'a bağlı dil sunucusu yok (:NoctisLang)"
end

local function m(mod)
  return require(mod)
end

-- ── Genel ────────────────────────────────────────────────────────────────
R.add({
  id = "palette",
  title = "Komut paleti",
  desc = "Tüm komutları adına, açıklamasına veya kısayoluna göre ara",
  group = "Genel",
  keys = "<leader><space>",
  run = function()
    m("noctis.palette").open()
  end,
})
R.add({
  id = "help",
  title = "Yardım ve kısayollar",
  desc = "Temel kullanım, modlar ve kısayol rehberi",
  group = "Genel",
  keys = "<leader>?",
  run = function()
    m("noctis.help").open()
  end,
})
R.add({
  id = "help.tutorial",
  title = "Bir dakikalık rehber",
  desc = "Dosya aç, yaz, kaydet, paleti aç, güvenli çık",
  group = "Genel",
  keys = "<leader>ht",
  run = function()
    m("noctis.onboarding").start()
  end,
})
R.add({
  id = "help.keys",
  title = "Tüm kısayolları ara",
  desc = "Etkin tüm eşlemeleri (eklentiler dahil) listele",
  group = "Genel",
  keys = "<leader>hk",
  run = function()
    m("noctis.help").keymaps()
  end,
})
R.add({
  id = "dashboard",
  title = "Başlangıç ekranı",
  desc = "Son dosyalar, son projeler ve hızlı eylemler",
  group = "Genel",
  keys = "<leader>hd",
  run = function()
    m("noctis.ui.dashboard").open({ force = true })
  end,
})
R.add({
  id = "health",
  title = "Sağlık kontrolü",
  desc = "Bağımlılıklar, terminal, clipboard ve AI profilleri (:checkhealth noctis)",
  group = "Genel",
  keys = "<leader>hh",
  run = function()
    vim.cmd("checkhealth noctis")
  end,
})
R.add({
  id = "plugins",
  title = "Eklenti yöneticisi",
  desc = "Lazy.nvim: durum, kilit dosyasına göre geri yükleme, güncelleme",
  group = "Genel",
  keys = "<leader>hp",
  check = plugin("lazy.nvim"),
  run = function()
    vim.cmd("Lazy")
  end,
})
R.add({
  id = "lang",
  title = "Dil paketleri",
  desc = "Python, JS/TS, HTML/CSS, JSON, Lua, Bash: sunucu/parser/formatter durumu ve kurulum",
  group = "Genel",
  keys = "<leader>hl",
  run = function()
    m("noctis.lang").open()
  end,
})
R.add({
  id = "config.open",
  title = "Kullanıcı ayarlarını aç",
  desc = "config.lua (güncellemeler bu dosyaya dokunmaz)",
  group = "Genel",
  keys = "<leader>hc",
  run = function()
    m("noctis.userconfig").open()
  end,
})

-- ── Dosya ────────────────────────────────────────────────────────────────
R.add({
  id = "files.find",
  title = "Dosya bul",
  desc = "Projede dosya adına göre bulanık arama (.gitignore'a uyar)",
  group = "Dosya",
  keys = "<leader>ff",
  run = function()
    m("noctis.pick").files()
  end,
})
R.add({
  id = "files.find_all",
  title = "Dosya bul (gizli + yok sayılanlar dahil)",
  desc = ".gitignore ile dışlanan ve gizli dosyaları da ara",
  group = "Dosya",
  keys = "<leader>fF",
  run = function()
    m("noctis.pick").files({ hidden = true, ignored = true })
  end,
})
R.add({
  id = "files.grep",
  title = "Projede metin ara",
  desc = "Önizlemeli canlı arama; sonuç doğru satıra götürür",
  group = "Dosya",
  keys = "<leader>fg",
  check = exe("rg", "ripgrep kurun"),
  run = function()
    m("noctis.pick").grep()
  end,
})
R.add({
  id = "files.grep_all",
  title = "Projede metin ara (yok sayılanlar dahil)",
  desc = ".gitignore ile dışlanan dosyalarda da ara",
  group = "Dosya",
  keys = "<leader>fG",
  check = exe("rg", "ripgrep kurun"),
  run = function()
    m("noctis.pick").grep({ hidden = true, ignored = true })
  end,
})
R.add({
  id = "files.grep_word",
  title = "İmleçteki kelimeyi ara",
  group = "Dosya",
  keys = "<leader>fw",
  check = exe("rg", "ripgrep kurun"),
  run = function()
    m("noctis.pick").grep({ word = true })
  end,
})
R.add({
  id = "files.buffers",
  title = "Açık buffer ara",
  group = "Dosya",
  keys = "<leader>fb",
  run = function()
    m("noctis.pick").buffers()
  end,
})
R.add({
  id = "files.recent",
  title = "Son dosyalar",
  group = "Dosya",
  keys = "<leader>fr",
  run = function()
    m("noctis.pick").recent()
  end,
})
R.add({
  id = "files.save",
  title = "Dosyayı kaydet",
  desc = "Diskteki sürüm dışarıdan değiştiyse önce sorar",
  group = "Dosya",
  keys = "<leader>fs",
  run = function()
    m("noctis.files").save()
  end,
})
R.add({
  id = "files.save_all",
  title = "Tüm değişmiş dosyaları kaydet",
  group = "Dosya",
  keys = "<leader>fS",
  run = function()
    m("noctis.files").save_all()
  end,
})
R.add({
  id = "files.new",
  title = "Yeni dosya",
  desc = "Proje kökünde yol sorarak dosya oluştur",
  group = "Dosya",
  keys = "<leader>fn",
  run = function()
    m("noctis.files").new_file()
  end,
})
R.add({
  id = "files.rename",
  title = "Dosyayı yeniden adlandır / taşı",
  group = "Dosya",
  keys = "<leader>fR",
  run = function()
    m("noctis.files").rename()
  end,
})
R.add({
  id = "files.delete",
  title = "Dosyayı sil (geri alınabilir)",
  desc = "Onay ister; dosya NOCTIS çöp kutusuna taşınır",
  group = "Dosya",
  keys = "<leader>fD",
  run = function()
    m("noctis.files").delete()
  end,
})
R.add({
  id = "files.trash",
  title = "Çöp kutusu: silineni geri yükle",
  group = "Dosya",
  keys = "<leader>fT",
  run = function()
    m("noctis.trash").pick()
  end,
})
R.add({
  id = "explorer",
  title = "Dosya gezginini aç/kapat",
  desc = "Git durumu, gizli dosyalar (H), yok sayılanlar (I)",
  group = "Dosya",
  keys = "<leader>e",
  run = function()
    m("noctis.explorer").toggle()
  end,
})

-- ── Proje ────────────────────────────────────────────────────────────────
R.add({
  id = "project.recent",
  title = "Son projeler",
  group = "Proje",
  keys = "<leader>pp",
  run = function()
    m("noctis.project").pick_recent()
  end,
})
R.add({
  id = "project.open",
  title = "Proje aç (klasör seç)",
  group = "Proje",
  keys = "<leader>po",
  run = function()
    m("noctis.project").open_prompt()
  end,
})
R.add({
  id = "project.set_root",
  title = "Proje kökünü elle belirle",
  desc = "Git kökü yanlışsa veya yoksa aktif kökü değiştir",
  group = "Proje",
  keys = "<leader>pr",
  run = function()
    m("noctis.project").set_root_prompt()
  end,
})
R.add({
  id = "project.tasks",
  title = "Görev çalıştır (run/test/build)",
  desc = "Seçilen komutu terminalde başlatır; kendiliğinden hiçbir şey çalışmaz",
  group = "Terminal",
  keys = "<leader>tr",
  run = function()
    m("noctis.tasks").pick()
  end,
})
R.add({
  id = "project.task_stop",
  title = "Çalışan görevi iptal et",
  group = "Terminal",
  keys = "<leader>tx",
  run = function()
    m("noctis.tasks").stop()
  end,
})

-- ── Ara / Değiştir ───────────────────────────────────────────────────────
R.add({
  id = "replace.project",
  title = "Projede bul ve değiştir (önizlemeli)",
  desc = "Kapsam ve tüm değişiklikler uygulanmadan önce gösterilir",
  group = "Ara / Değiştir",
  keys = "<leader>sr",
  check = exe("rg", "ripgrep kurun"),
  run = function()
    m("noctis.replace").open()
  end,
})
R.add({
  id = "search.buffer",
  title = "Bu dosyada satır ara",
  group = "Ara / Değiştir",
  keys = "<leader>sb",
  run = function()
    m("noctis.pick").lines()
  end,
})

-- ── Buffer / Pencere ─────────────────────────────────────────────────────
R.add({
  id = "buffer.delete",
  title = "Buffer'ı güvenli kapat",
  desc = "Kaydedilmemiş değişiklik varsa sorar; pencere düzeni korunur",
  group = "Buffer",
  keys = "<leader>bd",
  run = function()
    m("noctis.buffers").delete()
  end,
})
R.add({
  id = "buffer.others",
  title = "Diğer buffer'ları kapat",
  desc = "Kaydedilmemiş olanlar açık kalır",
  group = "Buffer",
  keys = "<leader>bo",
  run = function()
    m("noctis.buffers").delete_others()
  end,
})
R.add({
  id = "window.vsplit",
  title = "Dikey böl",
  group = "Pencere",
  keys = "<leader>wv",
  run = function()
    vim.cmd("vsplit")
  end,
})
R.add({
  id = "window.split",
  title = "Yatay böl",
  group = "Pencere",
  keys = "<leader>ws",
  run = function()
    vim.cmd("split")
  end,
})
R.add({
  id = "window.close",
  title = "Pencereyi kapat",
  desc = "Buffer açık kalır",
  group = "Pencere",
  keys = "<leader>wd",
  run = function()
    m("noctis.buffers").close_window()
  end,
})
R.add({
  id = "window.equal",
  title = "Pencere boyutlarını eşitle",
  group = "Pencere",
  keys = "<leader>w=",
  run = function()
    vim.cmd("wincmd =")
  end,
})

-- ── Çıkış / Oturum ───────────────────────────────────────────────────────
R.add({
  id = "quit",
  title = "Güvenli çık",
  desc = "Kaydedilmemiş dosyaları ve çalışan terminal/AI süreçlerini göstererek çıkar",
  group = "Çıkış / Oturum",
  keys = "<leader>qq",
  run = function()
    m("noctis.quit").quit()
  end,
})
R.add({
  id = "session.restore",
  title = "Proje oturumunu geri yükle",
  desc = "Açık dosyalar ve düzen; kaydedilmemiş buffer'ların üzerine yazmaz",
  group = "Çıkış / Oturum",
  keys = "<leader>qr",
  run = function()
    m("noctis.session").restore()
  end,
})
R.add({
  id = "session.save",
  title = "Oturumu şimdi kaydet",
  group = "Çıkış / Oturum",
  keys = "<leader>qs",
  run = function()
    m("noctis.session").save({ notify = true })
  end,
})

-- ── Terminal ─────────────────────────────────────────────────────────────
R.add({
  id = "terminal.toggle",
  title = "Terminal panelini aç/kapat",
  desc = "Gizlemek süreci öldürmez; Ctrl-\\ e ile editöre dönülür",
  group = "Terminal",
  keys = "<leader>tt",
  run = function()
    m("noctis.terminal").toggle()
  end,
})
R.add({
  id = "terminal.new",
  title = "Yeni terminal",
  group = "Terminal",
  keys = "<leader>tn",
  run = function()
    m("noctis.terminal").new()
  end,
})
R.add({
  id = "terminal.pick",
  title = "Terminaller arasında geç",
  group = "Terminal",
  keys = "<leader>ts",
  run = function()
    m("noctis.terminal").pick()
  end,
})

-- ── AI Workbench ─────────────────────────────────────────────────────────
R.add({
  id = "ai.toggle",
  title = "AI Workbench'i aç/kapat",
  desc = "Gizlemek AI sürecini durdurmaz",
  group = "AI",
  keys = "<leader>aa",
  run = function()
    m("noctis.ai").toggle()
  end,
})
R.add({
  id = "ai.new",
  title = "Yeni AI oturumu",
  desc = "Araç seç (Codex, Claude Code, Kimi Code, özel); önce inceleme başlangıcı kaydedilir",
  group = "AI",
  keys = "<leader>an",
  run = function()
    m("noctis.ai").new_session()
  end,
})
R.add({
  id = "ai.switch",
  title = "AI oturumları arasında geç",
  group = "AI",
  keys = "<leader>as",
  run = function()
    m("noctis.ai").switch()
  end,
})
R.add({
  id = "ai.review",
  title = "AI aralığındaki değişiklikleri incele",
  desc = "İnceleme başlangıcından bu yana tespit edilen dosya değişiklikleri",
  group = "AI",
  keys = "<leader>ad",
  run = function()
    m("noctis.ai").review()
  end,
})
R.add({
  id = "ai.checkpoint",
  title = "İnceleme aralığını kapat, yeni başlangıç al",
  desc = "Dosyaları değiştirmez; yalnız yeni bir başlangıç kaydı oluşturur",
  group = "AI",
  keys = "<leader>ac",
  run = function()
    m("noctis.ai").new_interval()
  end,
})
R.add({
  id = "ai.focus",
  title = "AI terminaline odaklan",
  group = "AI",
  keys = "<leader>af",
  run = function()
    m("noctis.ai").focus()
  end,
})
R.add({
  id = "ai.stop",
  title = "AI oturumunu durdur",
  desc = "Onay ister; süreç sonlandırılır",
  group = "AI",
  keys = "<leader>ax",
  run = function()
    m("noctis.ai").stop()
  end,
})
R.add({
  id = "ai.restart",
  title = "AI oturumunu yeniden başlat",
  group = "AI",
  keys = "<leader>ar",
  run = function()
    m("noctis.ai").restart()
  end,
})
R.add({
  id = "ai.resume",
  title = "AI aracının önceki oturumuna devam et",
  desc = "Yalnız aracın belgelenmiş devam etme bayrağıyla (claude -c, codex resume --last, kimi -c)",
  group = "AI",
  keys = "<leader>aR",
  run = function()
    m("noctis.ai").new_session({ resume = true })
  end,
})
R.add({
  id = "ai.revert_hunk",
  title = "Bu hunk'ı inceleme başlangıcına döndür",
  desc = "Editördeki dosyada imleçteki aralık değişikliği; disk incelenen sürümle aynı olmalı",
  group = "AI",
  keys = "<leader>ah",
  run = function()
    m("noctis.ai.review").current_revert_hunk()
  end,
})
R.add({
  id = "ai.revert_file",
  title = "Bu dosyayı inceleme başlangıcına döndür",
  desc = "Onay ister; önceki içerik yoksa yapılmaz; mevcut içerik önce yedeklenir",
  group = "AI",
  keys = "<leader>aU",
  run = function()
    m("noctis.ai.review").current_revert_file()
  end,
})
R.add({
  id = "ai.reviewed",
  title = "Bu dosyayı incelendi olarak işaretle",
  desc = "İçerik yeniden değişirse işaret kendiliğinden geçersizleşir",
  group = "AI",
  keys = "<leader>am",
  run = function()
    m("noctis.ai.review").current_mark_reviewed()
  end,
})
R.add({
  id = "ai.scope",
  title = "İnceleme kapsamını göster",
  desc = "Başlangıç kaydına alınan / dışlanan dosyalar ve sınırlar",
  group = "AI",
  keys = "<leader>ai",
  run = function()
    m("noctis.ai").scope_info()
  end,
})
R.add({
  id = "ai.context",
  title = "Seçimi AI'a bağlam olarak hazırla",
  desc = "İçerik önce gösterilir; onaylanmadan gönderilmez",
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
  title = "Git görünümü",
  desc = "Lazygit varsa onu açar; yoksa NOCTIS Git özeti",
  group = "Git",
  keys = "<leader>gg",
  run = function()
    m("noctis.git").view()
  end,
})
R.add({
  id = "git.status",
  title = "Git değişen dosyalar",
  group = "Git",
  keys = "<leader>gs",
  check = exe("git"),
  run = function()
    m("noctis.git").status()
  end,
})
R.add({
  id = "git.diff_file",
  title = "Dosya diff'i (Git)",
  desc = "Çalışma ağacı ile index/HEAD arasındaki fark",
  group = "Git",
  keys = "<leader>gd",
  check = exe("git"),
  run = function()
    m("noctis.git").diff_file()
  end,
})
R.add({
  id = "git.hunk_preview",
  title = "Hunk önizle",
  group = "Git",
  keys = "<leader>gp",
  check = plugin("gitsigns.nvim"),
  run = function()
    require("gitsigns").preview_hunk()
  end,
})
R.add({
  id = "git.blame_line",
  title = "Satırın blame bilgisi",
  group = "Git",
  keys = "<leader>gb",
  check = plugin("gitsigns.nvim"),
  run = function()
    require("gitsigns").blame_line({ full = true })
  end,
})
R.add({
  id = "git.hunk_reset",
  title = "Hunk'ı geri al (Git)",
  desc = "Onay ister; yalnız imleçteki hunk",
  group = "Git",
  keys = "<leader>gr",
  check = plugin("gitsigns.nvim"),
  run = function()
    m("noctis.git").reset_hunk()
  end,
})

-- ── Kod ──────────────────────────────────────────────────────────────────
R.add({
  id = "code.action",
  title = "Code action",
  group = "Kod",
  keys = "<leader>ca",
  mode = { "n", "x" },
  check = lsp_attached,
  run = function()
    vim.lsp.buf.code_action()
  end,
})
R.add({
  id = "code.rename",
  title = "Sembolü yeniden adlandır",
  group = "Kod",
  keys = "<leader>cr",
  check = lsp_attached,
  run = function()
    vim.lsp.buf.rename()
  end,
})
R.add({
  id = "code.format",
  title = "Dosyayı biçimlendir",
  group = "Kod",
  keys = "<leader>cf",
  mode = { "n", "x" },
  run = function()
    m("noctis.format").format()
  end,
})
R.add({
  id = "code.definition",
  title = "Tanıma git",
  group = "Kod",
  keys = "<leader>cd",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("definitions")
  end,
})
R.add({
  id = "code.references",
  title = "Referanslar",
  group = "Kod",
  keys = "<leader>cu",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("references")
  end,
})
R.add({
  id = "code.symbols",
  title = "Dosyadaki semboller",
  group = "Kod",
  keys = "<leader>cs",
  check = lsp_attached,
  run = function()
    m("noctis.pick").lsp("symbols")
  end,
})
R.add({
  id = "code.hover",
  title = "Belgeyi göster (hover)",
  desc = "Kısayol: K",
  group = "Kod",
  check = lsp_attached,
  run = function()
    vim.lsp.buf.hover()
  end,
})
R.add({
  id = "code.lsp_info",
  title = "Dil sunucusu durumu",
  group = "Kod",
  keys = "<leader>cl",
  run = function()
    vim.cmd("checkhealth vim.lsp")
  end,
})
R.add({
  id = "format.toggle",
  title = "Kaydederken biçimlendirmeyi aç/kapat (dosya türü)",
  desc = "Varsayılan kapalı; bu oturum için geçerli",
  group = "Kod",
  keys = "<leader>uf",
  run = function()
    m("noctis.format").toggle_on_save()
  end,
})

-- ── Tanılama ─────────────────────────────────────────────────────────────
R.add({
  id = "diag.list",
  title = "Diagnostics listesi (proje)",
  group = "Tanılama",
  keys = "<leader>xx",
  run = function()
    m("noctis.pick").diagnostics()
  end,
})
R.add({
  id = "diag.buffer",
  title = "Diagnostics (bu dosya)",
  group = "Tanılama",
  keys = "<leader>xb",
  run = function()
    m("noctis.pick").diagnostics({ buffer = true })
  end,
})
R.add({
  id = "diag.line",
  title = "Satırdaki tanılamayı göster",
  group = "Tanılama",
  keys = "<leader>xl",
  run = function()
    vim.diagnostic.open_float()
  end,
})
R.add({
  id = "diag.quickfix",
  title = "Quickfix listesi",
  group = "Tanılama",
  keys = "<leader>xq",
  run = function()
    m("noctis.ui.layout").toggle_qf()
  end,
})

-- ── Arayüz ───────────────────────────────────────────────────────────────
R.add({
  id = "ui.theme",
  title = "Tema seç",
  desc = "Midnight Violet, Glacier, Amber",
  group = "Arayüz",
  keys = "<leader>ut",
  run = function()
    m("noctis.theme").pick()
  end,
})
R.add({
  id = "ui.focus",
  title = "Odak modunu aç/kapat",
  desc = "Yan panelleri gizler, kodu ortalar",
  group = "Arayüz",
  keys = "<leader>uz",
  run = function()
    m("noctis.ui.layout").toggle_focus()
  end,
})
R.add({
  id = "ui.relnum",
  title = "Göreli satır numaraları",
  group = "Arayüz",
  keys = "<leader>un",
  run = function()
    vim.o.relativenumber = not vim.o.relativenumber
  end,
})
R.add({
  id = "ui.wrap",
  title = "Satır kaydırma (wrap)",
  group = "Arayüz",
  keys = "<leader>uw",
  run = function()
    vim.wo.wrap = not vim.wo.wrap
  end,
})
R.add({
  id = "ui.diagnostics",
  title = "Diagnostics görünürlüğü",
  group = "Arayüz",
  keys = "<leader>ud",
  run = function()
    local on = not vim.diagnostic.is_enabled()
    vim.diagnostic.enable(on)
    U.info("Diagnostics " .. (on and "açık" or "gizli"))
  end,
})
R.add({
  id = "ui.typing",
  title = "Yazma animasyonu",
  desc = "Yazılan karakterin kısa parlamasını aç/kapat (bu oturum için)",
  group = "Arayüz",
  keys = "<leader>ua",
  run = function()
    require("noctis.ui.typing").toggle()
  end,
})
R.add({
  id = "ui.inlay",
  title = "Inlay hint'ler",
  group = "Arayüz",
  keys = "<leader>uh",
  check = lsp_attached,
  run = function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
  end,
})

return R
