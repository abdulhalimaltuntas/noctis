-- Buffer yönetimi: kaydedilmemiş değişiklikleri ve pencere düzenini koruyarak kapatma.
local M = {}

local U = require("noctis.util")
local api = vim.api

local function listed_file_bufs(except)
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= except and vim.bo[b].buflisted and api.nvim_buf_is_loaded(b) then
      out[#out + 1] = b
    end
  end
  return out
end

local function job_running(buf)
  local chan = vim.bo[buf].channel
  if chan and chan > 0 then
    local ok, pid = pcall(vim.fn.jobpid, chan)
    return ok and pid and pid > 0
  end
  return false
end

--- Buffer'ı kapat; onu gösteren pencereler başka bir buffer'a geçer.
---@param buf? integer
---@param opts? {force?:boolean}
function M.delete(buf, opts)
  opts = opts or {}
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  local name = api.nvim_buf_get_name(buf)
  local label = name == "" and "[adsız]" or vim.fn.fnamemodify(name, ":~:.")

  if not opts.force and vim.bo[buf].modified then
    local choice = vim.fn.confirm(
      ("`%s` kaydedilmemiş değişiklikler içeriyor."):format(label),
      "&Kaydet ve kapat\n&Değişiklikleri at ve kapat\n&İptal",
      3
    )
    if choice == 1 then
      require("noctis.files").save(buf)
      if vim.bo[buf].modified then
        return -- kaydetme çatışma vb. nedeniyle tamamlanmadı
      end
    elseif choice ~= 2 then
      return
    end
  end
  if not opts.force and vim.bo[buf].buftype == "terminal" and job_running(buf) then
    if vim.fn.confirm(("`%s` içinde çalışan bir süreç var. Sonlandırılsın mı?"):format(label), "&Evet\n&Hayır", 2) ~= 1 then
      return
    end
  end

  -- Pencereleri boşaltmadan önce yerine geçecek buffer seç.
  local others = listed_file_bufs(buf)
  local alt = vim.fn.bufnr("#")
  local replacement = (alt > 0 and alt ~= buf and vim.bo[alt].buflisted) and alt or others[#others]
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf and api.nvim_win_get_config(win).relative == "" then
      if replacement then
        api.nvim_win_set_buf(win, replacement)
      else
        api.nvim_win_call(win, function()
          vim.cmd("enew")
        end)
      end
    end
  end
  if api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
end

function M.delete_others()
  local cur = api.nvim_get_current_buf()
  local kept = 0
  for _, b in ipairs(listed_file_bufs(cur)) do
    if vim.bo[b].modified or (vim.bo[b].buftype == "terminal" and job_running(b)) then
      kept = kept + 1
    else
      pcall(api.nvim_buf_delete, b, {})
    end
  end
  if kept > 0 then
    U.info(("%d buffer açık bırakıldı (kaydedilmemiş veya çalışan süreç)."):format(kept))
  end
end

function M.close_window()
  local normal = vim.tbl_filter(function(w)
    return api.nvim_win_get_config(w).relative == ""
  end, api.nvim_tabpage_list_wins(0))
  if #normal <= 1 and #api.nvim_list_tabpages() == 1 then
    U.info("Son pencere kapatılmaz. Buffer kapatmak: Space b d · Çıkmak: Space q q")
    return
  end
  vim.cmd("close")
end

return M
