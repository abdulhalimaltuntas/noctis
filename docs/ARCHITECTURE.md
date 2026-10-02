# Mimari

```
bin/noctis                  Başlatıcı (bash): bayraklar, NVIM_APPNAME, -u app/init.lua, exec
app/BRAND                   Ürün adı / komut / appname / sürüm — tek kaynak
app/init.lua                Giriş noktası; başlatma hatası → log + görünür hata + --safe önerisi
app/lazy-lock.json          Eklenti kilit dosyası (sürüm kontrolünde)
app/examples/config.lua     Açıklamalı kullanıcı ayarı örneği
app/colors/*.lua            :colorscheme giriş noktaları
app/lua/noctis/
  init.lua                  Orkestrasyon (her alt sistem ayrı korumalı adım)
  config.lua                Varsayılanlar + şema doğrulaması (config.lua kullanıcıda)
  options.lua · keymaps.lua · autocmds.lua · usercmds.lua
  registry.lua · commands.lua   Komut kaydı: palet, kısayollar, which-key, KEYMAPS.md
  palette.lua · pick.lua · explorer.lua · help.lua · onboarding.lua
  theme/{palettes,tokens,highlights,init}.lua   Tasarım sistemi
  ui/{statusline,tabline,dashboard,layout,float,bar,icons}.lua
  sync.lua                  Buffer ↔ disk senkronu, çatışma, 3 yollu birleştirme
  files.lua · trash.lua · buffers.lua · quit.lua · session.lua · project.lua
  terminal.lua · tasks.lua · replace.lua · git.lua · format.lua · lang.lua
  bigfile.lua · clipboard.lua · doctor.lua · health.lua · setup.lua · lazy.lua
  plugins/{snacks,editor,coding}.lua   lazy.nvim eklenti tanımları
  ai/
    profiles.lua · sessions.lua · workbench.lua · init.lua   Süreç/oturum tarafı
    store.lua · scope.lua · baseline.lua · watcher.lua · tracker.lua   Değişiklik tespiti
    hunks.lua · review.lua                                             İnceleme/geri alma
scripts/install.sh · scripts/uninstall.sh
tools/noctis-fake-ai        Deterministik test CLI'si
tests/                      launcher, çekirdek, AI, güvenli mod, eklenti, LSP, performans, görsel
```

## Temel kararlar

**Neovim çekirdeği, özgün Lua katmanı.** Metin motoru, Vim yorumlayıcısı,
terminal emülatörü, undo, swap ve diff Neovim'den gelir. NOCTIS bunları
yeniden yazmaz; deneyimi, veri güvenliği kurallarını ve AI Workbench'i ekler.
Minimum Neovim 0.12.0'dır: `vim.text.diff`, `jobstart({term=true})`,
`vim.lsp.config/enable` ve nvim-treesitter'ın `main` dalı bunu gerektirir.
Test edilen sürüm 0.12.4'tür.

**Ayrık uygulama ve kullanıcı dizinleri.** Başlatıcı `NVIM_APPNAME=noctis`
ve `-u <app>/init.lua` kullanır. Uygulama dosyaları (`~/.local/share/noctis/app`)
güncellemede tümüyle değiştirilir; kullanıcı ayarı (`~/.config/noctis/config.lua`)
hiç dokunulmayan ayrı bir dosyadır. Kullanıcının normal Neovim kurulumu
etkilenmez; NOCTIS içindeki terminaller kullanıcının özgün `NVIM_APPNAME`
değerini geri alır.

**Açık kurulum, ağsız açılış.** lazy.nvim yalnız `noctis --setup` sırasında
önyüklenir; `install.missing`, güncelleme denetimi ve değişiklik algılama
normal açılışta kapalıdır. Eksik eklenti tek bir uyarıyla bildirilir, editör
temel modda çalışır; tekrar eden indirme döngüsü yoktur.

**Tek kaynaktan komutlar.** `commands.lua` her komutu kimlik, ad, açıklama,
grup, varsayılan kısayol, kullanılabilirlik denetimi ve eylemle tanımlar.
Palet, Normal mod eşlemeleri, which-key grupları, `:Noctis <id>`, yardım
ekranı ve `docs/KEYMAPS.md` buradan üretilir. Kullanıcı override'ları komut
kimliğiyle yapılır; çakışma/önek denetimi testlerde ve `:checkhealth`'te çalışır.
Kullanılamayan komut (eksik eklenti, `rg`, LSP) gerekçesiyle gösterilir.

**Tasarım sistemi.** Varyantlar yalnız 11 temel token + 8 söz dizimi tonu
tanımlar; seçim, arama, diff, diagnostics zeminleri gibi türetilmiş tonlar
`tokens.lua`'da aynı formülle üretilir. Bileşenler renk değil highlight grubu
kullanır; tema değişince statusline, tabline, gezgin, completion, Git,
diagnostics ve Workbench birlikte güncellenir. Truecolor yoksa her renk en
yakın xterm-256 rengine eşlenir. WCAG kontrastları ölçüldü (ana metin 14.9:1,
yorumlar ≥4.4:1).

**Veri güvenliği katmanı (`sync.lua`).** Neovim'in `FileChangedShell`
mekanizması üzerine kurulur: temiz buffer'da güvenli reload (görünüm
korunur, değişen satırlar vurgulanır, `undoreload` ile geri alınabilir),
kirli buffer'da asla otomatik reload/save yok. Her buffer için "son senkron
içerik" ve disk imzası (mtime ns, boyut, inode) tutulur; kaydetmeden önce disk
yeniden denetlenir. Birleştirme `git merge-file` ile yapılır (Git deposu
gerekmez). Silme NOCTIS çöp kutusuna taşıma ile yapılır (sistem çöp kutusuna
bağımlı değil). Kalıcı undo ve swap açık kalır.

**AI: süreç yönetimi ile değişiklik tespiti ayrıdır.** `sessions.lua` yalnız
PTY süreçlerini yönetir. `tracker.lua` herhangi bir programın dosya
değişikliğini, hangi programın yaptığını varsaymadan izler; AI oturumu olmadan
da çalışır. Başlangıç kaydı içerik adreslidir (sha256), tekrarsızdır ve proje
dışında saklanır. İzleme dizin başınadır (Linux'ta `recursive` yok); olaylar
debounce + yazma durulma denetiminden geçer, kaçırılanlar düşük sıklıklı
uzlaştırmayla yakalanır. Geri alma satırları terminatörleriyle (`\n`/`\r\n`)
işleyerek bayt düzeyinde kesindir ve disk içeriğinin incelenen sürümle
aynı olmasını şart koşar.

**Toplu değiştirme.** Önizleme ve uygulama aynı motoru (ripgrep `--replace`)
kullanır; Lua desenleri ile Rust regex arasında anlam farkı oluşmaz. Uygulama
sırasında her satırın hâlâ önizlenen orijinal olduğu doğrulanır. Çıktı
`vim.system`'in metin normalizasyonu olmadan okunur (CRLF korunur).

## Eklenti seçimi (her yetenek için tek çözüm)

| Yetenek | Seçim | Gerekçe |
| --- | --- | --- |
| Eklenti yönetimi | lazy.nvim | Kilit dosyası, gecikmeli yükleme, `restore`; şartnamenin varsayılanı |
| Picker + gezgin + bildirim + input + odak modu + lazygit | snacks.nvim | Tek bağımlılıkta birden çok yetenek; ayrı picker/gezgin yok. Dashboard, bigfile, statusline kapalı — NOCTIS'in kendi modülleri |
| Kısayol yardımı | which-key.nvim | Gruplar registry'den gelir; terminal modunda tetiklenmez |
| Completion | blink.cmp (Lua eşleştirici) | Ön seçim ve otomatik ekleme kapalı; tür/kaynak sütunu. Rust ikilisi indirmez |
| LSP yapılandırmaları | nvim-lspconfig + `vim.lsp.enable` | Yerleşik LSP istemcisi; yalnız executable'ı bulunan sunucular etkinleştirilir |
| Söz dizimi | nvim-treesitter (`main`) | Parser'lar isteğe bağlı; yoksa Vim söz dizimi |
| Git işaretleri | gitsigns.nvim | Satır işaretleri, hunk önizleme/geri alma, blame |
| Biçimlendirme | conform.nvim | `stop_after_first`, LSP yalnız yedek, zaman aşımı |
| Araç kurulumu | mason.nvim | Yalnız kullanıcı başlattığında; PATH'e NOCTIS ekler |
| İkonlar | mini.icons | İkonlar açıkken yüklenir; her zaman kurulu (terminal değişince ağ gerekmez) |

Yazılmayan/kullanılmayan: bufferline, lualine, noice, telescope, nvim-cmp,
neo-tree — aynı işi gören ikinci bir çözüm yüklenmez.

## Gecikmeli yükleme

`snacks.nvim` ve `nvim-treesitter` (eklenti tembel yüklemeyi desteklemez)
açılışta yüklenir; which-key `VeryLazy`, blink.cmp `InsertEnter`/`CmdlineEnter`,
lspconfig ve gitsigns `BufReadPre`, conform `BufWritePre`/komut, mason komutla.
Palet veya kısayolla çağrılan henüz yüklenmemiş bir özellik `require` ile
lazy.nvim tarafından yüklenir (testte doğrulandı).

## Bilinçli olarak yapılmayanlar

Telemetri, otomatik güncelleme, proje içi Lua/config'in güvensiz çalıştırılması
(proje görev dosyası yalnız `vim.secure` güven onayıyla okunur), AI aracını
kendiliğinden başlatma, terminal dökümünü saklama, API anahtarı saklama.
