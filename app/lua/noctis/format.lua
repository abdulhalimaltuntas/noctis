-- Biçimlendirme. Kaydederken biçimlendirme varsayılan olarak kapalıdır ve
-- dosya türüne göre açılır. Aynı kayıtta tek formatter çalışır
-- (stop_after_first + LSP yalnız yedek). Hata/zaman aşımı kaydı engellemez,
-- görünür bildirim üretir.
local M = {}

local U = require("noctis.util")

---@type table<string, boolean> bu oturumda dosya türü bazında açık/kapalı
M.session_ft = {}

function M.enabled_for(buf)
  local cfg = require("noctis.config").options.format_on_save
  local ft = vim.bo[buf].filetype
  if vim.b[buf].noctis_bigfile then
    return false
  end
  if M.session_ft[ft] ~= nil then
    return M.session_ft[ft]
  end
  if not cfg.enabled then
    return false
  end
  return #cfg.filetypes == 0 or vim.tbl_contains(cfg.filetypes, ft)
end

function M.on_save_opts(buf)
  if not M.enabled_for(buf) then
    return nil
  end
  return { timeout_ms = require("noctis.config").options.format_on_save.timeout_ms, lsp_format = "fallback" }
end

function M.toggle_on_save()
  local ft = vim.bo.filetype
  if ft == "" then
    U.info("Bu buffer'ın dosya türü yok.")
    return
  end
  local now = not M.enabled_for(0)
  M.session_ft[ft] = now
  U.info(("Kaydederken biçimlendirme (%s): %s — kalıcı yapmak için config.lua › format_on_save"):format(ft, now and "AÇIK" or "kapalı"))
end

function M.format()
  local ok, conform = pcall(require, "conform")
  if ok then
    local mode = vim.fn.mode()
    local range
    if mode == "v" or mode == "V" then
      local s, e = vim.fn.line("v"), vim.fn.line(".")
      range = { start = { math.min(s, e), 0 }, ["end"] = { math.max(s, e), 0 } }
    end
    conform.format({ async = true, lsp_format = "fallback", range = range }, function(err, did_edit)
      if err then
        U.error("Biçimlendirme başarısız: " .. tostring(err))
      elseif did_edit == false then
        U.info("Değişiklik yok (zaten biçimli veya formatter yok: :NoctisLang)")
      end
    end)
    return
  end
  local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/formatting" })
  if #clients > 0 then
    vim.lsp.buf.format({ async = true })
  else
    U.info("Bu dosya türü için formatter yok. Durum: :NoctisLang")
  end
end

return M
