# Performans

## Açılış süresi

Ölçülen değer, Neovim'in `--startuptime` çıktısındaki **"first screen update"**
anıdır: süreç başlangıcından ilk ekranın çizilmesine kadar geçen süre (ms).
Ölçüm gerçek bir TUI içinde (tmux, 120×35, `TERM=tmux-256color`) yapılır.

- **Soğuk**: işletim sistemi sayfa önbelleği boşaltılmış (`drop_caches`, root)
  ve Lua bytecode / lazy.nvim önbelleği boş. 3 çalıştırmanın medyanı.
- **Sıcak**: önbellekler dolu; 1 ısınma + 10 ardışık çalıştırmanın medyanı ve aralığı.
- Eklenti kurulum süresi (`noctis --setup`) bu ölçüme **dahil değildir**.
- Neovim 0.10+ TUI istemcisi ve gömülü sunucu aynı dosyaya ayrı bloklar yazar;
  betik sunucu bloğundaki değeri okur.

Komut: `DATA=<eklentili XDG_DATA_HOME> tests/perf.sh 10`

### Sonuçlar (2026-10-02)

Makine: Intel Xeon @ 2.10 GHz, 4 çekirdek, 15 GiB RAM (bulut sanal makinesi),
Linux 6.18, Neovim 0.12.4, 10 eklenti kurulu.

| Senaryo | Soğuk (medyan) | Sıcak (medyan) | Sıcak aralık |
| --- | --- | --- | --- |
| Başlangıç ekranı (argümansız) | 70.2 ms | 41.0 ms | 38.7–59.0 ms |
| Python dosyası (`main.py`) | 122.6 ms | 58.2 ms | 56.4–67.1 ms |
| Güvenli mod (`--safe`) | 43.0 ms | 29.9 ms | 28.4–34.7 ms |

~300 ms ilk ekran hedefinin altında kalınmıştır. Python dosyasıyla açılışta
lspconfig ve gitsigns `BufReadPre` ile yüklenir; dil sunucusunun (pyright)
başlaması ve ilk analizi ilk ekrandan **sonra**, arka planda gerçekleşir
(pyright'ın soğuk analizi bu makinede birkaç saniye ile 15+ saniye arasında
değişti).

Farklı donanımda sonuçlar değişir; kendi makinenizde aynı betikle ölçün.

## Değişiklik takibi gecikmesi

`tests/lua/test_ai.lua`, dış bir sürecin (test CLI'si) dosyaya yazmayı
bitirmesinden değişikliğin listede görünmesine kadar geçen süreyi ölçer:
**~370 ms** (debounce 250 ms + yazma durulma denetimi 120 ms + diff).
Hedef ~1 sn'dir. Başlangıç kaydı küçük bir projede (9 dosya) ~25 ms sürdü;
kayıt arayüzü bloklamadan ~12 ms'lik parçalarla alınır.

## Büyük dosyalar

Varsayılan eşik 2 MiB veya 50.000 satırdır (`bigfile` ayarı). Eşiği aşan
dosyada söz dizimi, Tree-sitter, LSP, katlama ve görünür boşluk/imleç satırı
kapatılır; dosya düzenlenebilir kalır, swap ve undo korunur ve statusline'da
**BÜYÜK DOSYA** etiketi görünür.
