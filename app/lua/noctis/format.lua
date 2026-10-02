-- Formatting. Format-on-save is off by default and can be enabled per
-- filetype. Only one formatter runs per save (stop_after_first + LSP only as
-- a fallback). Errors/timeouts never block the save; they produce a visible
-- notification.
local M = {}

local U = require("noctis.util")

---@type table<string, boolean> per-filetype on/off for this session
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
    U.info("This buffer has no filetype.")
    return
  end
  local now = not M.enabled_for(0)
  M.session_ft[ft] = now
  U.info(("Format on save (%s): %s — to make it permanent use config.lua › format_on_save"):format(ft, now and "ON" or "off"))
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
        U.error("Formatting failed: " .. tostring(err))
      elseif did_edit == false then
        U.info("No changes (already formatted, or no formatter: :NoctisLang)")
      end
    end)
    return
  end
  local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/formatting" })
  if #clients > 0 then
    vim.lsp.buf.format({ async = true })
  else
    U.info("No formatter for this filetype. Status: :NoctisLang")
  end
end

return M
