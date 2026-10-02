-- NOCTIS çekirdek orkestrasyonu.
local M = {}

M.started_at = vim.uv.hrtime()

local function step(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    -- Tek bir alt sistemin hatası tüm editörü kullanılamaz yapmamalı;
    -- ama sessizce yutulmaz: log + görünür hata.
    local U = require("noctis.util")
    U.log("ERROR", ("%s kurulumu başarısız:\n%s"):format(name, err))
    U.error(("%s başlatılamadı: %s\nLog: %s"):format(name, tostring(err):match("^[^\n]*"), vim.fn.stdpath("state") .. "/noctis.log"))
  end
  return ok
end

function M.setup()
  local brand = require("noctis.brand")
  if vim.fn.has("nvim-" .. brand.min_nvim) == 0 then
    error(("%s için Neovim >= %s gerekli (mevcut: %s)"):format(brand.name, brand.min_nvim, tostring(vim.version())))
  end
  require("noctis.util").title = brand.name

  local cfg = require("noctis.config")
  cfg.load()

  require("noctis.options").setup()
  step("tema", function()
    require("noctis.theme").setup()
    require("noctis.theme").apply()
  end)
  step("otomatik komutlar", function()
    require("noctis.autocmds").setup()
  end)
  step("kısayollar", function()
    require("noctis.keymaps").setup()
  end)
  step("kullanıcı komutları", function()
    require("noctis.usercmds").setup()
  end)
  step("arayüz", function()
    require("noctis.ui").setup()
  end)
  step("proje", function()
    require("noctis.project").setup()
  end)

  if require("noctis.util").is_safe_mode() then
    M.plugins = false
  else
    step("eklentiler", function()
      M.plugins = require("noctis.lazy").setup()
    end)
  end

  step("AI Workbench", function()
    require("noctis.ai").setup()
  end)
  step("oturum", function()
    require("noctis.session").setup()
  end)
  step("başlangıç ekranı", function()
    require("noctis.ui.dashboard").setup()
  end)

  cfg.report()
end

return M
