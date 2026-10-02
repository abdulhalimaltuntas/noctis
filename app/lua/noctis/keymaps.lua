-- Kısayollar. Leader tabanlı eşlemeler registry'den gelir; burada yalnızca
-- mod bazlı küçük ergonomi eşlemeleri var. Temel Vim hareket, arama ve
-- düzenleme davranışları değiştirilmez.
local M = {}

local map = vim.keymap.set

function M.setup()
  require("noctis.commands")
  require("noctis.registry").apply_keymaps()

  -- Normal mod: pencereler arası geçiş
  map("n", "<C-h>", "<C-w>h", { desc = "Soldaki pencere" })
  map("n", "<C-j>", "<C-w>j", { desc = "Alttaki pencere" })
  map("n", "<C-k>", "<C-w>k", { desc = "Üstteki pencere" })
  map("n", "<C-l>", "<C-w>l", { desc = "Sağdaki pencere" })
  -- Esc: arama vurgusunu temizle (Normal modda)
  map("n", "<Esc>", "<cmd>nohlsearch<cr><Esc>", { desc = "Arama vurgusunu temizle" })

  -- Ek kolay kayıt (tek yol değil: Space f s de çalışır). Insert modda
  -- Ctrl-S, Neovim'in LSP imza yardımı için ayrılmış olarak kalır.
  map({ "n", "x" }, "<C-s>", function()
    require("noctis.registry").run("files.save")
  end, { desc = "Dosyayı kaydet" })

  -- Visual: girintilemede seçimi koru
  map("x", "<", "<gv", { desc = "Girintiyi azalt" })
  map("x", ">", ">gv", { desc = "Girintiyi artır" })

  -- Terminal modu: Esc ve Ctrl-C uygulamaya (shell / AI CLI) gider.
  -- Çıkış yolları Neovim'in <C-\> önekiyle, ayrı ve görünür tanımlıdır:
  --   Ctrl-\ Ctrl-n  terminalde Normal moda geç (yerleşik)
  --   Ctrl-\ e       editör penceresine dön
  map("t", "<C-\\>e", function()
    require("noctis.ui.layout").focus_editor()
  end, { desc = "Editöre dön" })
end

return M
