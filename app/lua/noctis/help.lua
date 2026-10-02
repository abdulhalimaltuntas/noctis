-- Yardım: modlar, temel akış, terminalden dönüş ve gruplu kısayollar.
-- Kısayol bölümü registry'den üretilir (komut paleti ile aynı kaynak).
local M = {}

local R = require("noctis.registry")

function M.lines()
  local brand = require("noctis.brand")
  local out = {
    "# " .. brand.name .. " — hızlı yardım",
    "",
    brand.name .. " Neovim tabanlıdır: modal düzenleme korunur.",
    "",
    "## Modlar",
    "  NORMAL  gezinme ve komutlar. Yazmak için  i",
    "  INSERT  metin yazma. Bitirmek için  Esc",
    "  VISUAL  seçim:  v  (karakter)  V  (satır). y kopyala · d sil · Esc bitir",
    "",
    "## Temel akış",
    "  Space f f   dosya bul           i / Esc   yaz / Normal moda dön",
    "  Space f s   kaydet              Space Space   komut paleti",
    "  Space b d   buffer'ı kapat      Space q q     güvenli çık",
    "  u / Ctrl-r  geri al / yinele    /metin        dosyada ara (n/N sonraki)",
    "",
    "## Terminal ve AI panelinden dönüş",
    "  Terminalde Esc ve Ctrl-C uygulamaya gider (shell / AI aracı).",
    "  Ctrl-\\ e        editör penceresine dön",
    "  Ctrl-\\ Ctrl-n   terminalde Normal moda geç (kaydır, kopyala); i ile geri yaz",
    "  Space a a / Space t t   panelleri gizle/göster (süreç çalışmaya devam eder)",
    "",
    "## Pencereler ve buffer'lar",
    "  Ctrl-h/j/k/l  pencereler arası geç       [b / ]b  önceki/sonraki buffer",
    "  Üst çubuk açık dosyaları (buffer) gösterir. Neovim sekmeleri (tabpage) ayrı",
    "  bir kavramdır; yalnız birden fazla sekme varsa sağda \"sekme 2/3\" görünür.",
    "",
  }
  local by_group, order = {}, {}
  for _, c in ipairs(R.list) do
    local k = R.effective_keys(c)
    if k and c.palette ~= false then
      if not by_group[c.group] then
        by_group[c.group] = {}
        order[#order + 1] = c.group
      end
      table.insert(by_group[c.group], ("  %-14s %s"):format(R.pretty_keys(k), c.title))
    end
  end
  for _, g in ipairs(order) do
    out[#out + 1] = "## " .. g
    vim.list_extend(out, by_group[g])
    out[#out + 1] = ""
  end
  out[#out + 1] = "Tüm liste ve çakışma raporu: :NoctisKeys · Sağlık kontrolü: Space h h"
  return out
end

function M.open()
  require("noctis.ui.float").text(M.lines(), { title = "Yardım", ft = "markdown", width = 84 })
end

function M.keymaps()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker and not require("noctis.util").is_safe_mode() then
    return Snacks.picker.keymaps()
  end
  vim.cmd("map")
end

return M
