-- Dosya işlemleri: kaydet, farklı kaydet, yeni, yeniden adlandır, sil.
local M = {}

local U = require("noctis.util")
local api = vim.api

local function root()
  return require("noctis.project").root()
end

local function rel(path)
  return U.relpath(root(), path) or vim.fn.fnamemodify(path, ":~")
end

---@param buf? integer
function M.save(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  local bt = vim.bo[buf].buftype
  if bt == "acwrite" then
    api.nvim_buf_call(buf, function()
      vim.cmd("write")
    end)
    return
  elseif bt ~= "" then
    U.info("Bu pencere bir dosya değil; kaydedilecek bir şey yok.")
    return
  end
  if api.nvim_buf_get_name(buf) == "" then
    return M.save_as(buf)
  end
  if vim.bo[buf].readonly then
    local ok = vim.fn.confirm("Dosya salt okunur işaretli. Yine de yazılsın mı?", "&Evet\n&Hayır", 2) == 1
    if not ok then
      return
    end
  end
  local sync = require("noctis.sync")
  local changed = sync.disk_changed(buf)
  local c = vim.b[buf].noctis_conflict
  if changed or (c and c.reason ~= "markers") then
    return sync.resolve(buf, { on_save = true })
  end
  if c and c.reason == "markers" then
    local has_markers = false
    for _, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match("^<<<<<<< ") or l:match("^>>>>>>> ") then
        has_markers = true
        break
      end
    end
    if has_markers and vim.fn.confirm("Dosyada hâlâ çakışma işaretleri (<<<<<<< / >>>>>>>) var. Yine de kaydedilsin mi?", "&Kaydet\n&Vazgeç", 2) ~= 1 then
      return
    end
  end
  -- Disk sürümü kullanıcı tarafından kabul edildiyse (birleştirme) ve o andan
  -- beri değişmediyse, yerleşik "okunduktan sonra değişti" sorusu atlanır.
  local force = vim.b[buf].noctis_ack == true
  api.nvim_buf_call(buf, function()
    vim.cmd(force and "write!" or "write")
  end)
  if not vim.bo[buf].modified then
    vim.b[buf].noctis_ack = nil
  end
end

function M.save_all()
  local skipped = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype == "" then
      local name = api.nvim_buf_get_name(b)
      local sync = require("noctis.sync")
      if name == "" or sync.disk_changed(b) or sync.has_conflict(b) then
        skipped[#skipped + 1] = name == "" and "[adsız]" or rel(name)
      else
        api.nvim_buf_call(b, function()
          vim.cmd("write")
        end)
      end
    end
  end
  if #skipped > 0 then
    U.warn("Atlanan (adsız veya diskte değişmiş): " .. table.concat(skipped, ", ") .. "\nBunları tek tek kaydedin: Space f s")
  end
end

---@param buf? integer
function M.save_as(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  vim.ui.input({ prompt = "Kaydet: ", default = root() .. "/", completion = "file" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local path = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ":p")
    if vim.fn.isdirectory(path) == 1 then
      U.warn("Bu bir klasör; dosya adı girin.")
      return
    end
    if vim.uv.fs_stat(path) then
      if vim.fn.confirm(("`%s` zaten var. Üzerine yazılsın mı?"):format(rel(path)), "&Evet\n&Hayır", 2) ~= 1 then
        return
      end
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    api.nvim_buf_call(buf, function()
      vim.cmd("saveas! " .. vim.fn.fnameescape(path))
    end)
    require("noctis.sync").clear_conflict(buf)
  end)
end

function M.new_file()
  vim.ui.input({ prompt = "Yeni dosya (klasör için sonuna / ekleyin): ", default = root() .. "/", completion = "file" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    input = vim.trim(input)
    local path = vim.fn.fnamemodify(vim.fn.expand(input), ":p")
    if input:sub(-1) == "/" then
      vim.fn.mkdir(path, "p")
      U.info("Klasör oluşturuldu: " .. rel(path))
      return
    end
    if vim.uv.fs_stat(path) then
      U.info("Dosya zaten var; açılıyor.")
    else
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local ok, err = U.write_file(path, "")
      if not ok then
        U.error("Oluşturulamadı: " .. tostring(err))
        return
      end
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end)
end

--- Diskte yeniden adlandır, buffer'ı yeni yola bağla, LSP'ye bildir.
function M.rename(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  local old = api.nvim_buf_get_name(buf)
  if old == "" or vim.bo[buf].buftype ~= "" then
    U.warn("Yeniden adlandırılacak bir dosya yok.")
    return
  end
  if vim.bo[buf].modified then
    U.warn("Önce kaydedin (Space f s); kaydedilmemiş buffer yeniden adlandırılmaz.")
    return
  end
  vim.ui.input({ prompt = "Yeni yol: ", default = old, completion = "file" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local new = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ":p")
    if new == old then
      return
    end
    if vim.uv.fs_stat(new) then
      U.error(("`%s` zaten var; üzerine yazılmadı."):format(rel(new)))
      return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(new, ":h"), "p")
    -- LSP: willRename (snacks varsa onun yardımcısı ile)
    local has_snacks, Snacks = pcall(require, "snacks")
    if has_snacks and Snacks.rename then
      Snacks.rename.on_rename_file(old, new, function()
        M._do_rename(buf, old, new)
      end)
    else
      M._do_rename(buf, old, new)
    end
  end)
end

function M._do_rename(buf, old, new)
  local ok, err = vim.uv.fs_rename(old, new)
  if not ok then
    U.error("Yeniden adlandırılamadı: " .. tostring(err))
    return
  end
  local views = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
    end
  end
  api.nvim_buf_set_name(buf, new)
  api.nvim_buf_call(buf, function()
    vim.cmd("silent! edit!")
  end)
  -- nvim_buf_set_name eski ad için alternatif buffer bırakır; temizle.
  local alt = vim.fn.bufnr(old)
  if alt > 0 and alt ~= buf and not vim.bo[alt].modified then
    pcall(api.nvim_buf_delete, alt, { force = true })
  end
  for win, view in pairs(views) do
    pcall(api.nvim_win_call, win, function()
      vim.fn.winrestview(view)
    end)
  end
  U.info(("Yeniden adlandırıldı: %s → %s"):format(rel(old), rel(new)))
end

--- Dosyayı onayla NOCTIS çöp kutusuna taşı (Space f T ile geri yüklenir).
---@param path? string
function M.delete(path)
  local buf = api.nvim_get_current_buf()
  path = path or api.nvim_buf_get_name(buf)
  if path == "" or not vim.uv.fs_stat(path) then
    U.warn("Silinecek dosya bulunamadı.")
    return
  end
  local msg = ("`%s` silinsin mi?\nDosya NOCTIS çöp kutusuna taşınır; Space f T ile geri yüklenebilir."):format(rel(path))
  if vim.fn.confirm(msg, "&Sil\n&Vazgeç", 2) ~= 1 then
    return
  end
  local target = vim.fn.bufnr(path)
  if target > 0 and vim.bo[target].modified then
    if vim.fn.confirm("Bu dosyanın kaydedilmemiş değişiklikleri var ve kaybolacak. Devam?", "&Evet\n&Hayır", 2) ~= 1 then
      return
    end
  end
  local ok, err = require("noctis.trash").move(path)
  if not ok then
    U.error("Silinemedi: " .. tostring(err))
    return
  end
  if target > 0 then
    require("noctis.buffers").delete(target, { force = true })
  end
  U.info(("Çöp kutusuna taşındı: %s  (geri al: Space f T)"):format(rel(path)))
end

return M
