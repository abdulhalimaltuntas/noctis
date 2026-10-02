-- `noctis --setup`: eklentileri kilit dosyasındaki commit'lerle indirir.
-- Ne indirileceğini önce açıklar; sonucu çıkış koduyla bildirir.
-- Dil sunucuları/parser'lar indirilmez (kullanıcı :NoctisLang ile seçer).
local M = {}

local function out(s)
  io.stdout:write(s .. "\n")
end

function M.run()
  local lazy_ok = package.loaded["lazy"] ~= nil
  if not lazy_ok then
    out("lazy.nvim yüklenemedi (ağ bağlantısını ve git kurulumunu kontrol edin).")
    vim.cmd("cquit 1")
    return
  end
  local Config = require("lazy.core.config")
  local lock = require("noctis.util").json_read(require("noctis.lazy").lockfile) or {}
  out("")
  out("NOCTIS eklenti kurulumu")
  out("Hedef: " .. Config.options.root)
  out("Eklentiler (kilit dosyasındaki sürümler):")
  local names = vim.tbl_keys(Config.plugins)
  table.sort(names)
  for _, name in ipairs(names) do
    local l = lock[name]
    out(("  • %-22s %s"):format(name, l and (l.commit:sub(1, 7) .. " (" .. (l.branch or "?") .. ")") or "kilitsiz (en güncel uyumlu sürüm)"))
  end
  out("Dil sunucuları, formatter'lar ve Tree-sitter parser'ları indirilmez; NOCTIS içinde :NoctisLang ile seçerek kurulur.")
  out("")

  -- Kurulu olanları da kilit dosyasındaki commit'e getir
  if next(lock) then
    require("lazy").restore({ wait = true, show = false })
  else
    require("lazy").install({ wait = true, show = false })
  end

  local missing = {}
  for _, name in ipairs(names) do
    local p = Config.plugins[name]
    if not (p and p._.installed) then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    out("Kurulamayan eklentiler: " .. table.concat(missing, ", "))
    out("Ağ bağlantısını kontrol edip `noctis --setup` komutunu tekrar çalıştırın. Editör bu eklentiler olmadan da açılır.")
    vim.cmd("cquit 1")
    return
  end
  out(("Tamam: %d eklenti hazır. Normal açılış artık ağ gerektirmez."):format(#names))
  out("Sonraki adım: noctis --doctor  ·  noctis")
  vim.cmd("qall!")
end

return M
