# NOCTIS kısayolları ve komutları

> Bu dosya `app/lua/noctis/commands.lua` içindeki komut kaydından üretilir
> (`tests/gen-keymaps.sh`). Elle düzenlemeyin; test paketi güncelliğini denetler.

Tüm komutlar `Space Space` komut paletinden adıyla aranabilir. Tablo Normal mod içindir.

## Genel

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space Space` | Komut paleti | Tüm komutları adına, açıklamasına veya kısayoluna göre ara |
| `Space ?` | Yardım ve kısayollar | Temel kullanım, modlar ve kısayol rehberi |
| `Space h t` | Bir dakikalık rehber | Dosya aç, yaz, kaydet, paleti aç, güvenli çık |
| `Space h k` | Tüm kısayolları ara | Etkin tüm eşlemeleri (eklentiler dahil) listele |
| `Space h d` | Başlangıç ekranı | Son dosyalar, son projeler ve hızlı eylemler |
| `Space h h` | Sağlık kontrolü | Bağımlılıklar, terminal, clipboard ve AI profilleri (:checkhealth noctis) |
| `Space h p` | Eklenti yöneticisi | Lazy.nvim: durum, kilit dosyasına göre geri yükleme, güncelleme |
| `Space h l` | Dil paketleri | Python, JS/TS, HTML/CSS, JSON, Lua, Bash: sunucu/parser/formatter durumu ve kurulum |
| `Space h c` | Kullanıcı ayarlarını aç | config.lua (güncellemeler bu dosyaya dokunmaz) |

## Dosya

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space f f` | Dosya bul | Projede dosya adına göre bulanık arama (.gitignore'a uyar) |
| `Space f F` | Dosya bul (gizli + yok sayılanlar dahil) | .gitignore ile dışlanan ve gizli dosyaları da ara |
| `Space f g` | Projede metin ara | Önizlemeli canlı arama; sonuç doğru satıra götürür |
| `Space f G` | Projede metin ara (yok sayılanlar dahil) | .gitignore ile dışlanan dosyalarda da ara |
| `Space f w` | İmleçteki kelimeyi ara |  |
| `Space f b` | Açık buffer ara |  |
| `Space f r` | Son dosyalar |  |
| `Space f s` | Dosyayı kaydet | Diskteki sürüm dışarıdan değiştiyse önce sorar |
| `Space f S` | Tüm değişmiş dosyaları kaydet |  |
| `Space f n` | Yeni dosya | Proje kökünde yol sorarak dosya oluştur |
| `Space f R` | Dosyayı yeniden adlandır / taşı |  |
| `Space f D` | Dosyayı sil (geri alınabilir) | Onay ister; dosya NOCTIS çöp kutusuna taşınır |
| `Space f T` | Çöp kutusu: silineni geri yükle |  |
| `Space e` | Dosya gezginini aç/kapat | Git durumu, gizli dosyalar (H), yok sayılanlar (I) |

## Proje

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space p p` | Son projeler |  |
| `Space p o` | Proje aç (klasör seç) |  |
| `Space p r` | Proje kökünü elle belirle | Git kökü yanlışsa veya yoksa aktif kökü değiştir |

## Terminal

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space t r` | Görev çalıştır (run/test/build) | Seçilen komutu terminalde başlatır; kendiliğinden hiçbir şey çalışmaz |
| `Space t x` | Çalışan görevi iptal et |  |
| `Space t t` | Terminal panelini aç/kapat | Gizlemek süreci öldürmez; Ctrl-\ e ile editöre dönülür |
| `Space t n` | Yeni terminal |  |
| `Space t s` | Terminaller arasında geç |  |

## Ara / Değiştir

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space s r` | Projede bul ve değiştir (önizlemeli) | Kapsam ve tüm değişiklikler uygulanmadan önce gösterilir |
| `Space s b` | Bu dosyada satır ara |  |

## Buffer

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space b d` | Buffer'ı güvenli kapat | Kaydedilmemiş değişiklik varsa sorar; pencere düzeni korunur |
| `Space b o` | Diğer buffer'ları kapat | Kaydedilmemiş olanlar açık kalır |

## Pencere

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space w v` | Dikey böl |  |
| `Space w s` | Yatay böl |  |
| `Space w d` | Pencereyi kapat | Buffer açık kalır |
| `Space w =` | Pencere boyutlarını eşitle |  |

## Çıkış / Oturum

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space q q` | Güvenli çık | Kaydedilmemiş dosyaları ve çalışan terminal/AI süreçlerini göstererek çıkar |
| `Space q r` | Proje oturumunu geri yükle | Açık dosyalar ve düzen; kaydedilmemiş buffer'ların üzerine yazmaz |
| `Space q s` | Oturumu şimdi kaydet |  |

## AI

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space a a` | AI Workbench'i aç/kapat | Gizlemek AI sürecini durdurmaz |
| `Space a n` | Yeni AI oturumu | Araç seç (Codex, Claude Code, Kimi Code, özel); önce inceleme başlangıcı kaydedilir |
| `Space a s` | AI oturumları arasında geç |  |
| `Space a d` | AI aralığındaki değişiklikleri incele | İnceleme başlangıcından bu yana tespit edilen dosya değişiklikleri |
| `Space a c` | İnceleme aralığını kapat, yeni başlangıç al | Dosyaları değiştirmez; yalnız yeni bir başlangıç kaydı oluşturur |
| `Space a f` | AI terminaline odaklan |  |
| `Space a x` | AI oturumunu durdur | Onay ister; süreç sonlandırılır |
| `Space a r` | AI oturumunu yeniden başlat |  |
| `Space a R` | AI aracının önceki oturumuna devam et | Yalnız aracın belgelenmiş devam etme bayrağıyla (claude -c, codex resume --last, kimi -c) |
| `Space a h` | Bu hunk'ı inceleme başlangıcına döndür | Editördeki dosyada imleçteki aralık değişikliği; disk incelenen sürümle aynı olmalı |
| `Space a U` | Bu dosyayı inceleme başlangıcına döndür | Onay ister; önceki içerik yoksa yapılmaz; mevcut içerik önce yedeklenir |
| `Space a m` | Bu dosyayı incelendi olarak işaretle | İçerik yeniden değişirse işaret kendiliğinden geçersizleşir |
| `Space a i` | İnceleme kapsamını göster | Başlangıç kaydına alınan / dışlanan dosyalar ve sınırlar |
| `Space a e` | Seçimi AI'a bağlam olarak hazırla | İçerik önce gösterilir; onaylanmadan gönderilmez |

## Git

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space g g` | Git görünümü | Lazygit varsa onu açar; yoksa NOCTIS Git özeti |
| `Space g s` | Git değişen dosyalar |  |
| `Space g d` | Dosya diff'i (Git) | Çalışma ağacı ile index/HEAD arasındaki fark |
| `Space g p` | Hunk önizle |  |
| `Space g b` | Satırın blame bilgisi |  |
| `Space g r` | Hunk'ı geri al (Git) | Onay ister; yalnız imleçteki hunk |

## Kod

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space c a` | Code action |  |
| `Space c r` | Sembolü yeniden adlandır |  |
| `Space c f` | Dosyayı biçimlendir |  |
| `Space c d` | Tanıma git |  |
| `Space c u` | Referanslar |  |
| `Space c s` | Dosyadaki semboller |  |
| — | Belgeyi göster (hover) | Kısayol: K |
| `Space c l` | Dil sunucusu durumu |  |
| `Space u f` | Kaydederken biçimlendirmeyi aç/kapat (dosya türü) | Varsayılan kapalı; bu oturum için geçerli |

## Tanılama

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space x x` | Diagnostics listesi (proje) |  |
| `Space x b` | Diagnostics (bu dosya) |  |
| `Space x l` | Satırdaki tanılamayı göster |  |
| `Space x q` | Quickfix listesi |  |

## Arayüz

| Kısayol | Komut | Açıklama |
| --- | --- | --- |
| `Space u t` | Tema seç | Midnight Violet, Glacier, Amber |
| `Space u z` | Odak modunu aç/kapat | Yan panelleri gizler, kodu ortalar |
| `Space u n` | Göreli satır numaraları |  |
| `Space u w` | Satır kaydırma (wrap) |  |
| `Space u d` | Diagnostics görünürlüğü |  |
| `Space u a` | Yazma animasyonu | Yazılan karakterin kısa parlamasını aç/kapat (bu oturum için) |
| `Space u h` | Inlay hint'ler |  |

