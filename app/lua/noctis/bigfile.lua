-- Büyük dosya modu: ağır özellikleri (Tree-sitter, LSP, syntax, katlama,
-- satır vurguları) kapatır; dosya düzenlenebilir kalır.
local M = {}

local api = vim.api

--- Dosya eşiği aşıyor mu? (BufReadPre'de boyut; satır sayısı okunduktan sonra)
function M.is_big(path)
  local cfg = require("noctis.config").options.bigfile
  local st = path and path ~= "" and vim.uv.fs_stat(path)
  return st and st.size > cfg.size or false
end

function M.apply(buf)
  if vim.b[buf].noctis_bigfile then
    return
  end
  vim.b[buf].noctis_bigfile = true
  vim.b[buf].completion = false -- blink.cmp bu bayrağa uyar
  vim.bo[buf].syntax = ""
  vim.bo[buf].swapfile = true -- kurtarma korunur
  pcall(vim.treesitter.stop, buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win].foldmethod = "manual"
    vim.wo[win].list = false
    vim.wo[win].cursorline = false
    vim.wo[win].spell = false
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    pcall(vim.lsp.buf_detach_client, buf, client.id)
  end
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  require("noctis.util").info(("Büyük dosya modu: %s — söz dizimi, LSP ve ağır görsel özellikler kapalı."):format(name))
end

function M.setup(group)
  api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(ev)
      if M.is_big(ev.match) then
        vim.b[ev.buf].noctis_bigfile_pending = true
        vim.bo[ev.buf].undolevels = 1000
      end
    end,
  })
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(ev)
      local lines = require("noctis.config").options.bigfile.lines
      if vim.b[ev.buf].noctis_bigfile_pending or api.nvim_buf_line_count(ev.buf) > lines then
        vim.b[ev.buf].noctis_bigfile_pending = nil
        M.apply(ev.buf)
      end
    end,
  })
  -- Dosya türü algılaması BufReadPost'tan sonra söz dizimini yeniden açar
  api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      if vim.b[ev.buf].noctis_bigfile then
        vim.schedule(function()
          if api.nvim_buf_is_valid(ev.buf) then
            vim.bo[ev.buf].syntax = ""
            pcall(vim.treesitter.stop, ev.buf)
          end
        end)
      end
    end,
  })
  -- Büyük dosyalarda LSP bağlanmasını engelle
  api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      if vim.b[ev.buf].noctis_bigfile then
        vim.schedule(function()
          pcall(vim.lsp.buf_detach_client, ev.buf, ev.data.client_id)
        end)
      end
    end,
  })
end

return M
