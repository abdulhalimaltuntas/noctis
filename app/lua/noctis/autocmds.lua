-- Çekirdek otomatik komutlar.
local M = {}

local api = vim.api

function M.setup()
  local group = api.nvim_create_augroup("noctis_core", { clear = true })

  require("noctis.sync").setup()
  require("noctis.bigfile").setup(group)
  require("noctis.clipboard").setup()

  -- Kopyalanan bölgeyi kısa süre göster
  api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
      vim.hl.on_yank({ higroup = "Visual", timeout = 180 })
    end,
  })

  -- Dosya tekrar açıldığında son konuma dön
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype
      if ft == "gitcommit" or vim.b[ev.buf].noctis_lastpos then
        return
      end
      vim.b[ev.buf].noctis_lastpos = true
      local mark = api.nvim_buf_get_mark(ev.buf, '"')
      if mark[1] > 0 and mark[1] <= api.nvim_buf_line_count(ev.buf) then
        pcall(api.nvim_win_set_cursor, 0, mark)
      end
    end,
  })

  -- Kaydederken eksik üst klasörleri oluştur (yalnız normal dosyalar)
  api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function(ev)
      if ev.match:match("^%w%w+:[\\/][\\/]") then
        return
      end
      local dir = vim.fn.fnamemodify(vim.uv.fs_realpath(ev.match) or ev.match, ":p:h")
      if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
      end
    end,
  })

  -- Yardım/liste pencereleri q ile kapanır
  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "help", "qf", "checkhealth", "man", "lspinfo", "notify", "startuptime", "git", "noctis-info" },
    callback = function(ev)
      vim.bo[ev.buf].buflisted = false
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = ev.buf, silent = true, desc = "Kapat" })
    end,
  })

  -- Terminal buffer'ları: sade görünüm
  api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      vim.wo.number = false
      vim.wo.relativenumber = false
      vim.wo.signcolumn = "no"
      vim.wo.cursorline = false
      vim.wo.list = false
      vim.bo[ev.buf].buflisted = false
    end,
  })

  -- Pencere boyutu değişince bölmeleri dengele ve yerleşimi uyarla.
  -- Odak ve mod korunur: terminal/AI aracı yazma modundaysa (Ctrl-C, Esc
  -- uygulamaya gitmeli) yeniden boyutlandırmadan sonra da öyle kalır.
  -- `tabdo` pencereler arasında dolaşıp terminal modunu bitirdiği için diğer
  -- sekmeler ilk girişte dengelenir.
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      local term_mode = vim.fn.mode() == "t"
      local cur = api.nvim_get_current_tabpage()
      for _, tp in ipairs(api.nvim_list_tabpages()) do
        if tp ~= cur then
          vim.t[tp].noctis_equalize = true
        end
      end
      vim.cmd("wincmd =")
      api.nvim_exec_autocmds("User", { pattern = "NoctisResized", modeline = false })
      if term_mode then
        vim.schedule(function()
          if vim.bo.buftype == "terminal" and vim.fn.mode() ~= "t" then
            vim.cmd("startinsert")
          end
        end)
      end
    end,
  })
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if vim.t.noctis_equalize then
        vim.t.noctis_equalize = nil
        vim.cmd("wincmd =")
      end
    end,
  })

  -- Klasör argümanı (noctis .): klasörü proje olarak aç, gezgini göster
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      local arg = vim.fn.argv(0)
      if type(arg) == "string" and arg ~= "" and vim.fn.isdirectory(arg) == 1 then
        local dirbuf = api.nvim_get_current_buf()
        local path = vim.fn.fnamemodify(arg, ":p")
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        if require("noctis.util").is_safe_mode() then
          return -- netrw klasörü gösterir
        end
        vim.cmd("enew")
        if api.nvim_buf_is_valid(dirbuf) and vim.fn.isdirectory(api.nvim_buf_get_name(dirbuf)) == 1 then
          pcall(api.nvim_buf_delete, dirbuf, { force = true })
        end
        vim.schedule(function()
          pcall(function()
            require("noctis.explorer").open()
          end)
        end)
      end
    end,
  })

  -- Çöp kutusu bakımı arka planda
  vim.defer_fn(function()
    pcall(require("noctis.trash").prune)
  end, 3000)
end

return M
