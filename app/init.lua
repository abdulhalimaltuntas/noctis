-- NOCTIS giriş noktası. Launcher bu dosyayı `nvim -u <app>/init.lua` ile yükler.
-- Kullanıcı yapılandırması ayrı tutulur: stdpath("config")/config.lua

local home = vim.env.NOCTIS_HOME
if not home or home == "" then
  home = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
  vim.env.NOCTIS_HOME = home
end
vim.opt.rtp:prepend(home)

local ok, err = xpcall(function()
  require("noctis").setup()
end, debug.traceback)

if not ok then
  -- Gerçek yapılandırma hatalarını yutmayız: logla, göster, güvenli modu öner.
  pcall(function()
    require("noctis.util").log("ERROR", "başlatma hatası:\n" .. tostring(err))
  end)
  vim.schedule(function()
    vim.api.nvim_echo({
      { "NOCTIS başlatılamadı. ", "ErrorMsg" },
      { "Ayrıntı: :messages  ·  Log: " .. vim.fn.stdpath("state") .. "/noctis.log\n", "WarningMsg" },
      { "Eklentisiz açmak için: noctis --safe\n\n", "WarningMsg" },
      { tostring(err), "ErrorMsg" },
    }, true, {})
  end)
end
