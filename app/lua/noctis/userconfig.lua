-- Kullanıcı ayar dosyasını aç; yoksa açıklamalı örnekten oluştur.
local M = {}

function M.open()
  local cfg = require("noctis.config")
  local path = cfg.path
  if not vim.uv.fs_stat(path) then
    local example = require("noctis.brand").home .. "/examples/config.lua"
    local text = require("noctis.util").read_file(example)
      or "-- NOCTIS kullanıcı ayarları. Değişiklikler yeniden başlatınca uygulanır.\nreturn {\n  -- theme = \"glacier\",\n}\n"
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    require("noctis.util").write_file(path, text, 420)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  require("noctis.util").info("Ayarlar kaydedildikten sonra NOCTIS'i yeniden başlatın. Hatalı değerler açılışta açıklamalı olarak raporlanır.")
end

return M
