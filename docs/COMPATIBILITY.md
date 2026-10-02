# Doğrulama ve uyumluluk

Bu belge neyin **gerçekten çalıştırılarak** doğrulandığını, neyin
doğrulanmadığını ayırır. "Test edildi" yalnız bu depodaki otomatik testlerle
veya gerçek PTY oturumunda gözlemle doğrulanan şeyler için kullanılır.

Doğrulama ortamı: Linux 6.18 (x86_64, Ubuntu 24.04 tabanlı bulut sanal makinesi),
Neovim 0.12.4, git 2.43, ripgrep 14.1, tmux 3.4, Python 3.11, Node 22.
Tarih: 2026-10-02.

## Platformlar

| Platform | Durum | Not |
| --- | --- | --- |
| Linux x86_64 | ✅ Test edildi | Tüm otomatik testler + gerçek PTY görsel doğrulama |
| Linux arm64 | ⚪ Test edilmedi | Platforma özgü kod yok; çalışması beklenir |
| macOS | ⚪ Test edilmedi | POSIX araçları kullanılır (`cp -a`, `git`, `rg`). Dosya izleme dizin başına `fs_event` ile yazıldı; macOS'ta doğrulanmadı. `/proc` tabanlı inotify denetimi macOS'ta atlanır |
| Windows + WSL 2 | ⚪ Test edilmedi | Linux yolunun çalışması beklenir. `/mnt/c` gibi Windows dosya sistemlerinde inotify olayları güvenilir değildir; uzlaştırma taraması devreye girer |
| Windows (yerel) | ❌ Desteklenmiyor | Başlatıcı bash'tır; ilk sürümün hedefi değil |

## Neovim ve eklentiler

| Bileşen | Doğrulanan sürüm |
| --- | --- |
| Neovim | 0.12.4 (minimum 0.12.0; daha eski sürümler başlatıcı tarafından reddedilir — test edildi) |
| Eklentiler | `app/lazy-lock.json` içindeki commit'ler ([THIRD_PARTY.md](../THIRD_PARTY.md)) |

## AI araçları

| Araç | Sürüm | Durum |
| --- | --- | --- |
| Claude Code | 2.1.287 | ✅ PTY'de açılış/ilk kullanım ekranı, renkler, yeniden boyutlandırma, yazma modunun korunması gözlemlendi (görüntüler 13–15). Prompt gönderilmedi; oturum açma ve dosya yazma akışı bu ortamda doğrulanmadı |
| Codex CLI | — | ⚪ Kurulu değildi; doğrulanmadı. Bayraklar resmi kaynaktan doğrulandı |
| Kimi Code | — | ⚪ Kurulu değildi; doğrulanmadı. Bayraklar resmi belgelerden doğrulandı |
| Test CLI | 1.0 | ✅ Uçtan uca (dosya yazma türleri, Ctrl-C/SIGINT, çıkış kodu, gizliyken devam) |

## Dil sunucuları

| Dil | Doğrulanan | Durum |
| --- | --- | --- |
| Python | pyright, ruff | ✅ Gerçek sunucuyla diagnostics, completion, tanıma git, rename; ruff ile biçimlendirme ve format-on-save |
| Python Tree-sitter | parser v0.25.0 (tree-sitter CLI 0.27.0 ile derlendi) | ✅ Parser varken Tree-sitter vurgusu, yokken Vim söz dizimi. Not: bu ortamda nvim-treesitter'ın tarball indirmesi ağ politikası nedeniyle 403 aldı; parser git ile alınıp derlendi |
| JS/TS, HTML/CSS, JSON, Lua, Bash | — | ⚪ Paketler tanımlı, sunucular bu ortamda kurulu değildi; gerçek sunucuyla doğrulanmadı |

## Kabul kriterleri

| # | Kriter | Durum | Kanıt |
| --- | --- | --- | --- |
| 1 | Temiz geçici XDG'de kurulup açılır; mevcut Neovim ayarı etkilenmez | ✅ | `tests/install_test.sh`, tüm Lua testleri geçici XDG ile çalışır |
| 2 | Proje açılır; dosya bulunur, düzenlenir, kaydedilir, tekrar açıldığında doğru | ✅ | `test_plugins` (picker ile bul + aç), `test_core` (kaydet + yeniden aç) |
| 3 | Boşluk/Türkçe yol, `ğüşiİöç`, CRLF korunur | ✅ | `test_core`, `test_ai` (proje yolu `proje ğüşiİöç`), `launcher_test` |
| 4 | Kaydedilmemiş buffer kapatma/çıkışta korunur; iptal çalışır | ✅ | `test_core` |
| 5 | Dışarıdan değiştirilmiş dosya sessizce ezilmez | ✅ | `test_core`, `test_ai` |
| 6 | Arama doğru dosya/satıra götürür; toplu değiştirme önce gösterir | ✅ | `test_plugins` (grep → satır 3), `test_core` (önizleme, hariç tutma, CRLF, regex) |
| 7 | En az bir dilde completion, diagnostics, tanıma git, rename | ✅ | `test_lsp` (pyright) |
| 8 | Terminal çalışır; gizle/göster süreç ve çıktıyı korur; editöre dönülür | ✅ | `test_core`; `Ctrl-\ e` gerçek PTY'de (görüntü 15) |
| 9 | Git işaretleri gerçek diff ile tutarlı; Git olmayan klasör sorunsuz | ✅ | `test_plugins` (gitsigns ↔ `git diff --numstat`) |
| 10 | Küçük/büyük boyut, yeniden boyutlandırma, uzun ad, ikonsuz | ✅ | `test_plugins` (60–200 sütunda taşma yok, uzun ad), görüntüler 09, 12, 14 |
| 11 | Ağ yok, `rg`/dil sunucusu eksik, `--safe` | ✅ | `test_safe` (iki mod), `launcher_test` |
| 12 | Yeniden kurulum ayarları korur; kaldırma sınırları aşmaz | ✅ | `tests/install_test.sh` |
| 13 | AI profilleri ayrı PTY, doğru kök; gizle/değiştir/boyut/odak | ✅ | `test_ai` (PTY + sahte CLI), `test_plugins` (odak), gerçek Claude Code (13–15) |
| 14 | Başlangıç öncesi staged/unstaged/untracked korunur; Git ↔ aralık ayrı; index değişmez | ✅ | `test_ai` (index baytları karşılaştırılır) |
| 15 | Normal yazma, atomic-save, oluştur/sil, alt klasör; temiz buffer güncellenir; Git'siz proje | ✅ | `test_ai` |
| 16 | Kaydedilmemiş düzenleme + AI değişikliği: iki içerik korunur | ✅ | `test_ai` (çatışma, 3 yollu birleştirme), `test_core` (silinen dosya) |
| 17 | Seçili geri alma yalnız hedefi etkiler; inceleme sonrası değişiklikte reddedilir; index korunur | ✅ | `test_ai` |
| 18 | Birden çok CLI'de kaynak atanmaz; "çalışıyor" ≠ "tamamlandı" | ✅ | `test_ai` (iki oturum uyarısı, atıfsız değişiklik, kanıta dayalı durum) |
| 19 | Eksik executable, hatalı çıkış editörü bozmaz; açılışta AI başlamaz | ✅ / ⚪ | `test_ai`, `test_core`. Hesap yokluğu ve ağ kesintisi gerçek araçlarla bu ortamda **doğrulanmadı** (araç kendi arayüzünde gösterir; NOCTIS süreç çıkışını raporlar) |
| 20 | Kapsam sınırları, dışlananlar, büyük/binary dosyalar açıkça gösterilir; bilinmeyen içerikle geri alma vaat edilmez | ✅ | `test_ai` |

## Görsel doğrulama

Görüntüler `tests/visual/capture.sh` ile NOCTIS gerçek bir PTY'de (tmux)
çalışırken yakalanır ve HTML üzerinden PNG'ye çevrilir. Yakalama, terminalin o
anki hücre içeriği ve renkleridir. Sınırlama: görüntülerdeki font (DejaVu Sans
Mono + Nerd Font sembolleri) ve hücre aralığı sizin terminalinizden farklı
olabilir; görüntüler gerçek bir terminal emülatörünün ekran kaydı değildir.

Görsel incelemede bulunup düzeltilen hatalar (commit geçmişinde): Workbench
üst çubuğunun soldan kırpılması, yeniden boyutlandırmada terminal modunun
kaybolması (Ctrl-C'nin araca ulaşmaması), geçici diff buffer'larının sekme
çubuğunda görünmesi, gezgin boş satırlarının farklı zeminle çizilmesi,
komut paleti sıralaması.

## Doğrulanmayan / bilinen sınırlar

- macOS, WSL ve arm64 üzerinde çalıştırılmadı.
- Codex CLI ve Kimi Code gerçek oturumla denenmedi.
- Gerçek bir AI aracının dosya yazma akışı (hesapla) bu ortamda denenmedi;
  takip mantığı araçtan bağımsız olarak test CLI'siyle doğrulandı.
- JS/TS, HTML/CSS, JSON, Lua, Bash dil sunucuları gerçek sunucuyla denenmedi.
- Lazygit entegrasyonu (isteğe bağlı) lazygit kurulu olmadığı için denenmedi;
  yedek Git özeti test edildi.
- Sistem panosu sağlayıcısı bu ortamda yoktu; bu durum `noctis --doctor`
  çıktısında doğru algılandı. xclip/wl-clipboard ile kopyalama doğrulanmadı.
