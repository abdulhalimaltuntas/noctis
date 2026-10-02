# AI Workbench rehberi

AI Workbench, mevcut AI kodlama CLI'lerini (Codex CLI, Claude Code, Kimi Code
veya kendi tanımladığınız bir araç) NOCTIS içinde **gerçek terminal
oturumlarında** çalıştırır ve bu araçların (ya da başka herhangi bir programın)
proje dosyalarına yaptığı değişiklikleri canlı izler, incelemenizi ve gerekirse
korumalı biçimde geri almanızı sağlar.

NOCTIS yeni bir AI sohbet servisi veya model API katmanı değildir: aracın kendi
hesabını, oturum açma akışını, izinlerini ve ağ davranışını kullanır. NOCTIS API
anahtarı saklamaz, araç izinlerini değiştirmez, kaynak kodu veya terminal
dökümünü dış bir servise göndermez ve hiçbir AI aracını kendiliğinden başlatmaz.

![AI Workbench](screenshots/05-ai-workbench.png)

## Hızlı başlangıç

| Kısayol | İşlem |
| --- | --- |
| `Space a n` | Araç seç ve yeni oturum başlat (önce başlangıç kaydı alınır) |
| `Space a a` | Paneli göster → odakla → gizle (gizlemek süreci durdurmaz) |
| `Space a s` | Oturumlar ve "Değişiklikler" görünümü arasında geç |
| `Space a d` | İnceleme aralığındaki değişiklikleri göster |
| `Space a c` | Aralığı kapat, yeni başlangıç kaydı al (dosyalara dokunmaz) |
| `Space a f` | AI terminaline odaklan |
| `Space a h` / `a U` / `a m` | Editördeki dosyada: hunk geri al / dosyayı geri al / incelendi işaretle |
| `Space a i` | Kapsam ayrıntısı (kaydedilen / dışlanan dosyalar, sınırlar) |
| `Space a x` / `a r` | Oturumu durdur / yeniden başlat (onaylı) |
| `Space a R` | Aracın önceki oturumuna devam et (yalnız belgelenmiş bayrakla) |
| `Space a e` | Seçimi bağlam olarak hazırla (önce gösterilir; Enter gönderilmez) |
| `Ctrl-\ e` | AI terminalinden editöre dön |

Terminal odağındayken `Esc` ve `Ctrl-C` dahil tüm tuşlar araca gider (aracın
kendi davranışı korunur). Bu, gerçek PTY'de doğrulanmıştır: `Ctrl-C` araca
SIGINT olarak ulaşır ve oturum durumu kanıta göre "çıktı (130)" olur.

## Profiller

| Profil | Executable | Sürüm sorgusu | Devam (resume) | Kaynak |
| --- | --- | --- | --- | --- |
| Claude Code | `claude` | `claude --version` | `claude --continue` (dizindeki son konuşma) | [CLI reference](https://code.claude.com/docs/en/cli-reference) |
| Codex CLI | `codex` | `codex --version` | `codex resume --last` | [openai/codex](https://github.com/openai/codex) (`codex-rs/cli`), [belgeler](https://developers.openai.com/codex/cli) |
| Kimi Code | `kimi` | `kimi --version` | `kimi --continue` (dizindeki son oturum) | [kimi komutu](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html), [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) |
| Özel | sizin belirlediğiniz argüman dizisi | isteğe bağlı | — | `config.lua` |

Varsayılan başlatma **bayraksızdır** (aracın normal etkileşimli modu). Yukarıdaki
bayraklar yalnızca ilgili aracın resmi belgelerinde/kaynağında doğrulandığı için
kullanılır; başka bayrak eklenmez. Not: Python tabanlı eski `kimi-cli`
arşivlenmiştir; profil, yerine geçen Kimi Code CLI'yi (`kimi`) hedefler.

Program ve argümanlar kabuk metnine birleştirilmeden argüman dizisi olarak
verilir. Özel profil örneği (`~/.config/noctis/config.lua`):

```lua
return {
  ai = {
    profiles = {
      claude = { cmd = { "/opt/claude/bin/claude" } },       -- farklı konum
      aider = { label = "Aider", cmd = { "aider", "--no-auto-commits" } },
      codex = false,                                         -- listeden kaldır
    },
  },
}
```

Araç kurulu değilse oturum başlatılmaz; panel aranan executable'ı, resmi kurulum
komutunu ve belge bağlantısını gösterir. Editör etkilenmez.

## Proje bağlama ve oturumlar

- Her oturumun **sabit bir proje kökü**, araç etiketi, benzersiz kimliği ve
  terminal buffer'ı vardır. Başka bir projeye geçmek çalışan sürecin çalışma
  klasörünü değiştirmez; panel üst çubuğu oturumun kökünü gösterir.
- Birden fazla oturum açılabilir. Aynı çalışma ağacında ikinci bir araç
  başlatılırken eşzamanlı yazma riski için onay istenir ve panelde uyarı
  görünür. Önerilen kullanım: tek düzenleyen araç. NOCTIS diğer programların
  dosyaya yazmasını kilitleyemez.
- **Durum yalnız kanıta göre** gösterilir: *başlatılıyor* (süreç başladı, çıktı
  yok), *çalışıyor* (süreç canlı ve çıktı üretti), *çıktı (kod)*, *başlatılamadı*.
  "Görev tamamlandı", "onay bekliyor", token/maliyet gibi bilgiler terminal
  metninden tahmin edilmez ve gösterilmez. Sürecin açık olması görevin
  sürdüğünü, sessizlik bittiğini kanıtlamaz.
- `Space q q` ile çıkarken çalışan oturumlar listelenir; süreçler çıkışta
  sonlandırılır (arka planda kalma sözü verilmez).
- Yerleşim: geniş ekranda sağ panel, orta genişlikte alt panel, dar ekranda tam
  alan (tek görünümlü sekmeler). Pencere boyutu değişince yerleşim uyarlanır;
  odak ve terminal (yazma) modu korunur.

## İnceleme aralığı ve başlangıç kaydı

İlk AI oturumundan önce proje için bir **inceleme aralığı** başlatılır:

1. Kapsamdaki metin dosyalarının **o anki disk içeriği** yerel, içerik
   adresli bir depoya kopyalanır (yalnız hash değil — önceki içeriği
   gösterebilmek ve geri alabilmek için).
2. Git deposuysa mevcut commit, dal ve staged/unstaged/untracked durumu
   **salt okunur** kaydedilir (`git --no-optional-locks`; index yenilemesi
   bile yazılmaz). Branch, index, stash veya çalışma ağacı değiştirilmez —
   bu, testlerde index baytları karşılaştırılarak doğrulanır.
3. Kayıt tamamlanmadan araç başlatılmaz. Kayıt arayüzü bloklamadan parça parça
   alınır.

Bu sayede **başlangıçtan önce var olan kullanıcı düzenlemeleri yeni AI
değişikliği gibi gösterilmez**. İki karşılaştırma ayrı etiketlenir:

- **İnceleme aralığı** (varsayılan): başlangıç kaydından bu yana tespit edilen değişiklikler.
- **Git** (`g` tuşu): çalışma ağacının HEAD'e göre farkı (başlangıç öncesi düzenlemeler dahil).

Etkin aralık projeye bağlıdır ve NOCTIS yeniden açıldığında sürer (kapalıyken
olan değişiklikler açılışta uzlaştırmayla yakalanır). Araç veya proje
değiştirmek aralığı gizlice sıfırlamaz; yeni aralık yalnız `Space a c` ile başlar.

### Kapsam ve sınırlar

| Kural | Varsayılan |
| --- | --- |
| `.gitignore` / `.ignore` | uygulanır (Git deposu olmasa da) |
| Hiç izlenmeyen klasörler | `.git`, `node_modules`, `.venv`, `venv`, `__pycache__`, `dist`, `build`, `target`, `coverage`, önbellek klasörleri… |
| Hassas dosyalar | `.env*`, `*.pem`, `*.key`, `id_rsa*`, `.npmrc`, `.netrc`, `credentials`, `secrets.*` … içerikleri **asla kopyalanmaz** |
| Dosya başına boyut | 1 MiB (`ai.baseline.max_file_size`) |
| Toplam içerik | 64 MiB (`ai.baseline.max_total_size`) |
| İçeriği kaydedilen dosya sayısı | 5000 (`ai.baseline.max_files`) |
| Sembolik bağlantılar | takip edilmez; proje dışına giden yollar izlenmez ve geri alınmaz |
| Saklama | 14 gün, en çok 512 MB (`ai.retention_days`, `ai.max_store_mb`) |
| Konum | `~/.local/state/noctis/noctis/ai/<proje-anahtarı>/` (proje dışında, 0700) |

Kapsam dışı bir dosya değişirse listede görünür, ancak **önceki içerik
olmadığı** açıkça yazılır ve geri alma önerilmez. `Space a i` hangi dosyaların
neden dışlandığını listeler.

## Canlı takip

- Dosya oluşturma, değiştirme, silme, atomic-save (geçici dosya + rename),
  yeni alt klasörler izlenir. Linux'ta libuv'nin `recursive` bayrağı
  desteklenmediği (doğrulandı) için **her dizin ayrı izlenir** ve yeni dizinler
  olay geldikçe eklenir. İzleme sınırı aşılırsa kalan kısım periyodik
  uzlaştırmayla takip edilir ve bu panelde belirtilir.
- Olaylar birleştirilir; kısa bir yazma-durulma denetiminden sonra diff
  hesaplanır. Ölçülen gecikme: yazmanın bitişinden listede görünmeye
  **~370 ms** (test: `tests/lua/test_ai.lua`).
- Kaçırılan olaylar için odak dönüşünde ve düşük sıklıkta (varsayılan 4 sn)
  uzlaştırma yapılır; her tuşta proje taranmaz.
- Bildirimler toplanır (en fazla birkaç saniyede bir tek mesaj); yeni dosyaya
  zorla geçilmez. Kendi kaydettiğiniz dosyalar için bildirim gösterilmez
  (listede yine görünür).
- Gezginde aralıkta değişen dosyalar **A / M / D** ile işaretlenir.

**Kaynak atfı:** Dosya sistemi olayı değişikliği hangi programın yaptığını
söylemez. Bu yüzden değişiklikler hiçbir zaman belirli bir araca atanmaz;
etiket her zaman "inceleme aralığında tespit edilen değişiklik"tir. Siz veya
başka bir araç aynı sırada yazarsa bu değişiklikler de aralığa girer.

### Açık buffer davranışı

1. **Buffer temizse**: diskteki kararlı içerik yeniden yüklenir; imleç ve
   kaydırma korunur, değişen satırlar birkaç saniye ölçülü vurgulanır.
   Yeniden yükleme `u` ile geri alınabilir.
2. **Kaydedilmemiş düzenleme varsa**: otomatik yükleme veya kaydetme yapılmaz.
   Buffer **ÇATIŞMA** olarak işaretlenir; kaydederken disk yeniden denetlenir.
3. **Çatışmada** (`:NoctisConflict` veya kaydetme anında): karşılaştır,
   3 yollu birleştir (taban: buffer'ın en son senkronize olduğu içerik — bu,
   AI başlangıcıyla aynı olmak zorunda değildir), yerel sürümü yaz (ezilen disk
   içeriği yedeklenir), disk sürümünü yükle (yerel kopya önce saklanır) veya
   yerel içeriği ayrı dosyaya kopyala. Güvenilir taban yoksa manuel diff ve
   ayrı kopya yolu sunulur.
4. **Dosya silinmiş/taşınmışsa**: buffer içeriği kaybolmaz (değiştirilmiş
   sayılır, çıkışta sorulur); aynı yola veya yeni konuma kaydedebilirsiniz.

AI terminalinde gösterilen ama diske yazılmamış bir öneri dosya değişikliği
değildir; dosya durumu değişmeden hiçbir işaret konmaz.

## İnceleme ve geri alma

Değişiklik listesinde: `Enter` diff, `r` incelendi, `u` dosyayı geri al, `o` aç,
`g` Git görünümü, `R` yenile, `q` gizle.

- Geniş ekranda (≥140 sütun) **yan yana**, dar ekranda **birleşik** diff açılır.
  Ekleme/silme/değişiklik renkleri sabittir; dosya başına +/− satır sayısı
  gösterilir. Binary dosyalarda metin diff'i yerine boyut durumu gösterilir.
- **İncelendi** işareti içerik yeniden değişirse kendiliğinden geçersizleşir.
  Bu sürümde araç doğrudan çalışma ağacına yazdığı için inceleme **sonradan**
  yapılır; "incelendi" bir yazma öncesi onay değildir.
- **Geri alma** (`X` hunk, `U`/`u` dosya, editörde `Space a h` / `Space a U`):
  - Disk içeriği incelediğiniz sürümle hâlâ aynı olmalıdır; araya başka bir
    yazma girdiyse işlem reddedilir ve farkı yeniden incelemeniz istenir.
  - Dosyanın açık buffer'ında kaydedilmemiş düzenleme varsa reddedilir.
  - Yalnız seçilen hunk/dosya değişir; diğer değişiklikler, önceki kullanıcı
    düzenlemeleri ve Git index'i korunur. `git reset`, `git clean` veya proje
    çapında geri dönüş kullanılmaz.
  - Geri almadan önceki içerik `~/.local/state/noctis/noctis/recovered/`
    altına kopyalanır; eklenmiş bir dosyanın geri alınması onu NOCTIS çöp
    kutusuna taşır (`Space f T` ile geri gelir).
  - Önceki içerik yoksa (kapsam dışı) bu açıkça söylenir ve işlem yapılmaz.
- **Yeni aralık** (`Space a c`) dosyaları değiştirmez; eski kayıt saklama
  süresi boyunca durur.

## Bağlam gönderme

`Space a e` (Normal veya Visual mod) seçili kodu `yol:satır` başlığı ve kod
bloğu olarak hazırlar, **önce önizlemede gösterir**; onaylarsanız aracın giriş
satırına köşeli parantezli yapıştırma ile eklenir. Enter gönderilmez — aracın
içinde gözden geçirip kendiniz gönderirsiniz.

## Doğrulanmış uyumluluk

| Araç | Sürüm | Bu ortamda doğrulanan |
| --- | --- | --- |
| Claude Code | 2.1.287 | PTY'de açılış ve ilk kullanım ekranı (renkler, ASCII grafik, diff önizlemesi), 160→120 sütun yeniden boyutlandırmada yeniden çizim, panel yerleşim değişimi sırasında yazma modunun korunması. **Hiçbir prompt gönderilmedi**, ücretli görev başlatılmadı. Oturum açma ve dosya yazma akışı bu ortamda doğrulanmadı. |
| Codex CLI | — | Bu ortamda kurulu değil; **doğrulanmadı**. Bayraklar resmi kaynaktan doğrulandı. |
| Kimi Code | — | Bu ortamda kurulu değil; **doğrulanmadı**. Bayraklar resmi belgelerden doğrulandı. |
| Test CLI (`tools/noctis-fake-ai`) | 1.0 | Uçtan uca: PTY, ANSI renkleri, proje kökü, normal yazma, atomic-save, oluşturma/silme, alt klasör, `.gitignore`, gizliyken çalışmaya devam, Ctrl-C (SIGINT), çıkış kodu, eksik executable |

Test CLI'sinin başarılı olması, üç gerçek aracın da tam olarak test edildiği
anlamına gelmez.

## Bilinen sınırlar

- Değişiklikler yazıldıktan sonra incelenir; yazma öncesi kabul/ret (patch veya
  sandbox akışı) bu sürümde yoktur.
- Değişikliklerin kaynağı doğrulanamaz (bkz. kaynak atfı).
- Aracın kendi "onay bekliyor / bitti" durumu okunmaz.
- Panel temaya uyar; terminalin içindeki renkler ve kontrol dizileri aracındır
  (16 ANSI rengi temadan gelir; tema değişimi yalnız yeni oturumları etkiler).
