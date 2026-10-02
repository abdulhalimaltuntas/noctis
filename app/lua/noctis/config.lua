-- Kullanıcı yapılandırması: varsayılanlar + şema doğrulaması.
-- Kullanıcı dosyası: stdpath("config")/config.lua  (bir Lua tablosu döndürür)
-- Güncellemeler bu dosyaya asla dokunmaz.
local M = {}

M.defaults = {
  theme = "midnight-violet", -- "midnight-violet" | "glacier" | "amber"
  transparent = false, -- editör zemini terminalden gelsin mi
  icons = true, -- Nerd Font ikonları; false ise sade karakterler
  borders = "rounded", -- "rounded" | "single" | "ascii"
  truecolor = "auto", -- "auto" | true | false
  welcome = true, -- ilk açılışta kısa rehber
  ui = {
    relative_numbers = false,
    indent_guides = true,
    cursorline = true,
    explorer_width = 30,
    wrap = false,
    typing_animation = true, -- yazılan karakterin zemininde kısa parlama (truecolor gerekir)
  },
  diagnostics = {
    virtual_text = true,
    signs = true,
    underline = true,
  },
  format_on_save = {
    enabled = false,
    filetypes = {}, -- yalnız bu dosya türlerinde; boşsa ve enabled=true ise tümü
    timeout_ms = 1500,
  },
  languages = { "python", "javascript", "html", "json", "lua", "bash" },
  bigfile = {
    size = 2 * 1024 * 1024, -- bayt
    lines = 50000,
  },
  clipboard = "auto", -- "auto" | "system" | "internal"
  session = {
    autosave = true, -- çıkışta proje düzenini kaydet; geri yükleme her zaman açık komutla
  },
  keymaps = {}, -- { ["komut.id"] = "<leader>xy" | false }
  tasks = {}, -- { { name = "Test", cmd = { "pytest" }, cwd = nil } }
  ai = {
    profiles = {}, -- varsayılan profilleri genişlet/ez: { aider = { label = "Aider", cmd = { "aider" } } }
    layout = "auto", -- "auto" | "right" | "bottom" | "full"
    width = 0.42, -- sağ panel oranı
    height = 0.40, -- alt panel oranı
    baseline = {
      max_files = 5000,
      max_file_size = 1024 * 1024,
      max_total_size = 64 * 1024 * 1024,
      exclude = {}, -- ek dışlama desenleri (gitignore tarzı basit glob)
      respect_gitignore = true,
    },
    watch = {
      debounce_ms = 250,
      reconcile_ms = 4000,
      max_dirs = 4000,
    },
    retention_days = 14,
    max_store_mb = 512,
  },
}

-- Şema: varsayılanlar tipleri belirler; burada ek kısıtlar var.
local enums = {
  theme = { "midnight-violet", "glacier", "amber" },
  borders = { "rounded", "single", "ascii" },
  clipboard = { "auto", "system", "internal" },
  ["ai.layout"] = { "auto", "right", "bottom", "full" },
}
local special = {
  truecolor = function(v)
    return v == "auto" or type(v) == "boolean", '"auto", true veya false olmalı'
  end,
  ["ui.explorer_width"] = function(v)
    return type(v) == "number" and v >= 16 and v <= 80, "16 ile 80 arasında bir sayı olmalı"
  end,
  ["ai.width"] = function(v)
    return type(v) == "number" and v > 0.15 and v < 0.85, "0.15 ile 0.85 arasında oran olmalı"
  end,
  ["ai.height"] = function(v)
    return type(v) == "number" and v > 0.15 and v < 0.85, "0.15 ile 0.85 arasında oran olmalı"
  end,
}
-- İçeriği serbest olan (anahtarları kullanıcı belirleyen) alanlar
local open = {
  keymaps = true,
  tasks = true,
  languages = true,
  ["ai.profiles"] = true,
  ["format_on_save.filetypes"] = true,
  ["ai.baseline.exclude"] = true,
}

---@type string[]
M.errors = {}
---@type string[]
M.warnings = {}

local function is_list(t)
  return type(t) == "table" and (vim.tbl_isempty(t) or vim.islist(t))
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then
      return true
    end
  end
  return false
end

--- Kullanıcı tablosunu varsayılanlara karşı doğrula ve birleştir.
--- Geçersiz değerler raporlanır ve varsayılanla değiştirilir.
---@return table merged
function M.validate(user, defaults, prefix, errors, warnings)
  local out = vim.deepcopy(defaults)
  if type(user) ~= "table" then
    return out
  end
  for k, v in pairs(user) do
    local key = prefix and (prefix .. "." .. k) or tostring(k)
    local def = defaults[k]
    if def == nil and not special[key] then
      warnings[#warnings + 1] = ("bilinmeyen ayar `%s` yok sayıldı (yazım hatası olabilir)"):format(key)
    elseif special[key] then
      local ok, why = special[key](v)
      if ok then
        out[k] = v
      else
        errors[#errors + 1] = ("`%s` geçersiz: %s (verilen: %s)"):format(key, why, vim.inspect(v))
      end
    elseif open[key] then
      if type(v) ~= "table" then
        errors[#errors + 1] = ("`%s` bir tablo olmalı (verilen: %s)"):format(key, type(v))
      else
        out[k] = v
      end
    elseif type(def) == "table" and not is_list(def) then
      if type(v) ~= "table" then
        errors[#errors + 1] = ("`%s` bir tablo olmalı (verilen: %s)"):format(key, type(v))
      else
        out[k] = M.validate(v, def, key, errors, warnings)
      end
    elseif type(v) ~= type(def) then
      errors[#errors + 1] = ("`%s` için %s bekleniyordu, %s verildi"):format(key, type(def), type(v))
    elseif enums[key] and not contains(enums[key], v) then
      errors[#errors + 1] = ("`%s` şunlardan biri olmalı: %s (verilen: %s)"):format(
        key,
        table.concat(enums[key], ", "),
        tostring(v)
      )
    else
      out[k] = v
    end
  end
  return out
end

M.path = vim.fn.stdpath("config") .. "/config.lua"

---@type table
M.options = vim.deepcopy(M.defaults)

--- Kullanıcı dosyasını yükle. Sözdizimi hatası durumunda varsayılanlarla devam
--- edilir ve hata görünür kılınır (sessizce yutulmaz).
function M.load()
  M.errors, M.warnings = {}, {}
  local user = {}
  if vim.uv.fs_stat(M.path) then
    local chunk, lerr = loadfile(M.path)
    if not chunk then
      M.errors[#M.errors + 1] = "config.lua okunamadı: " .. tostring(lerr)
    else
      local ok, res = pcall(chunk)
      if not ok then
        M.errors[#M.errors + 1] = "config.lua çalıştırılırken hata: " .. tostring(res)
      elseif type(res) ~= "table" then
        M.errors[#M.errors + 1] = "config.lua bir tablo döndürmeli (örnek: return { theme = \"glacier\" })"
      else
        user = res
      end
    end
  end
  M.options = M.validate(user, M.defaults, nil, M.errors, M.warnings)
  -- Kalıcı tema seçimi (Space u t) kullanıcı dosyasında tema yoksa uygulanır.
  if user.theme == nil then
    local st = require("noctis.util").json_read(vim.fn.stdpath("state") .. "/noctis/ui.json")
    if st and contains(enums.theme, st.theme) then
      M.options.theme = st.theme
    end
  end
  return M.options
end

function M.report()
  local U = require("noctis.util")
  for _, e in ipairs(M.errors) do
    U.log("ERROR", "config: " .. e)
  end
  for _, w in ipairs(M.warnings) do
    U.log("WARN", "config: " .. w)
  end
  if #M.errors > 0 then
    U.error(
      "Yapılandırma hataları (varsayılanlar kullanıldı):\n• " .. table.concat(M.errors, "\n• ") .. "\nDosya: " .. M.path
    )
  end
  if #M.warnings > 0 then
    U.warn("Yapılandırma uyarıları:\n• " .. table.concat(M.warnings, "\n• "))
  end
end

setmetatable(M, {
  __index = function(_, k)
    return M.options[k]
  end,
})

return M
