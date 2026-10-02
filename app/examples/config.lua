-- NOCTIS kullanıcı ayarları
-- Konum: ~/.config/noctis/config.lua  (XDG_CONFIG_HOME'a uyar)
-- Güncellemeler bu dosyaya dokunmaz. Değişiklikler NOCTIS yeniden başlatılınca
-- uygulanır. Geçersiz değerler açılışta açıklamalı olarak raporlanır ve yerine
-- varsayılan kullanılır. Tüm alanlar isteğe bağlıdır.
return {
  -- Tema: "midnight-violet" | "glacier" | "amber"  (Space u t ile de seçilir)
  -- theme = "midnight-violet",

  -- Editör zemini terminalden gelsin (şeffaflık terminalinizin özelliğidir)
  -- transparent = false,

  -- Nerd Font ikonları. Font yoksa false yapın; arayüz eksiksiz çalışır.
  -- icons = true,

  -- Kenarlıklar: "rounded" | "single" | "ascii"
  -- borders = "rounded",

  -- Renk: "auto" (terminali sorgula) | true (24 bit) | false (256 renk yedeği)
  -- truecolor = "auto",

  -- İlk açılış rehberi
  -- welcome = true,

  ui = {
    -- relative_numbers = false,
    -- indent_guides = true,
    -- cursorline = true,
    -- explorer_width = 30, -- 16..80
    -- wrap = false,
  },

  diagnostics = {
    -- virtual_text = true,
    -- signs = true,
    -- underline = true,
  },

  -- Kaydederken biçimlendirme (varsayılan kapalı). Yalnız belirli türler için:
  format_on_save = {
    -- enabled = true,
    -- filetypes = { "python", "lua" }, -- boşsa tüm türler
    -- timeout_ms = 1500,
  },

  -- Etkin dil paketleri. Bileşenler kendiliğinden indirilmez (:NoctisLang)
  -- languages = { "python", "javascript", "html", "json", "lua", "bash" },

  -- Büyük dosya modu eşiği
  -- bigfile = { size = 2 * 1024 * 1024, lines = 50000 },

  -- Pano: "auto" | "system" | "internal"
  -- clipboard = "auto",

  -- Çıkışta proje düzenini kaydet (geri yükleme her zaman açık komutla: Space q r)
  -- session = { autosave = true },

  -- Kısayol değiştirme/kapatma: komut kimliği → tuş veya false.
  -- Kimlikler: :NoctisKeys  veya docs/KEYMAPS.md
  keymaps = {
    -- ["files.grep"] = "<leader>/",
    -- ["ui.focus"] = false,
  },

  -- Görevler (Space t r). Komutlar argüman dizisi olarak verilir; dizi yerine
  -- metin verilirse kabukta çalıştırılır. Hiçbiri kendiliğinden başlamaz.
  tasks = {
    -- { name = "Testler", cmd = { "pytest", "-q" } },
    -- { name = "Sunucu", cmd = { "npm", "run", "dev" } },
  },

  ai = {
    -- Profiller: yerleşikleri (claude, codex, kimi) genişletin veya ekleyin.
    -- cmd her zaman argüman dizisidir; kabuk metnine birleştirilmez.
    profiles = {
      -- claude = { cmd = { "/opt/claude/bin/claude" } },          -- farklı konum
      -- codex = false,                                            -- listeden kaldır
      -- aider = { label = "Aider", cmd = { "aider", "--no-auto-commits" } },
      -- ozel = { label = "Kendi aracım", cmd = { "benim-aracim" }, env = { MY_MODE = "1" } },
    },
    -- layout = "auto", -- "auto" | "right" | "bottom" | "full"
    -- width = 0.42,    -- sağ panel oranı
    -- height = 0.40,   -- alt panel oranı
    baseline = {
      -- max_files = 5000,
      -- max_file_size = 1024 * 1024,
      -- max_total_size = 64 * 1024 * 1024,
      -- exclude = { "*.sqlite", "data/**" },
      -- respect_gitignore = true,
    },
    watch = {
      -- debounce_ms = 250,
      -- reconcile_ms = 4000,
      -- max_dirs = 4000,
    },
    -- retention_days = 14,
    -- max_store_mb = 512,
  },
}
