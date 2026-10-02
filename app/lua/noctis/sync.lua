-- Buffer ↔ disk senkronizasyonu ve çatışma yönetimi.
--
-- Kurallar:
--   * Temiz buffer: disk değişince güvenle yeniden yüklenir; görünüm korunur,
--     değişen satırlar kısa süre vurgulanır, yeniden yükleme `u` ile geri alınabilir
--     ('undoreload').
--   * Kaydedilmemiş buffer: otomatik reload/save YOK. Buffer çatışmalı işaretlenir;
--     kaydetmede güncel disk sürümü yeniden denetlenir.
--   * Çatışma: yerel buffer, güncel disk ve buffer'ın en son senkronize olduğu
--     içerik (taban) üzerinden karşılaştırma/birleştirme sunulur. Taban yoksa
--     manuel diff ve ayrı kopya kaydetme yolu sunulur.
--   * Silinen/taşınan dosya: buffer içeriği kaybedilmez (değiştirilmiş işaretlenir).
local M = {}

local U = require("noctis.util")
local api = vim.api

local ns = api.nvim_create_namespace("noctis.sync")

---@type table<integer, string> buffer -> son senkron içerik (disk ile eşit olduğu bilinen)
M.base = {}
---@type table<integer, {mtime:integer, nsec:integer, size:integer, ino:integer}?> son senkron disk durumu
M.stat = {}
M.MAX_BASE = 4 * 1024 * 1024

local function is_file_buf(buf)
  return api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= ""
end

--- Buffer içeriğini diske yazılacak biçimde metne çevir.
function M.buf_text(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local nl = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
  local text = table.concat(lines, nl)
  if vim.bo[buf].endofline or vim.bo[buf].fixendofline then
    text = text .. nl
  end
  return text
end

--- Bu buffer için taban (son senkron içerik) kaydet.
function M.remember(buf)
  if not is_file_buf(buf) then
    M.base[buf], M.stat[buf] = nil, nil
    return
  end
  local st = vim.uv.fs_stat(api.nvim_buf_get_name(buf))
  M.stat[buf] = st and { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino } or nil
  if vim.b[buf].noctis_bigfile then
    M.base[buf] = nil
    return
  end
  local text = M.buf_text(buf)
  if #text <= M.MAX_BASE then
    M.base[buf] = text
  else
    M.base[buf] = nil
  end
end

local function views_for(buf)
  local views = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
    end
  end
  return views
end

local function restore_views(buf, views)
  local count = api.nvim_buf_line_count(buf)
  for win, view in pairs(views) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      view.lnum = math.min(view.lnum, count)
      view.topline = math.min(view.topline, count)
      pcall(api.nvim_win_call, win, function()
        vim.fn.winrestview(view)
      end)
    end
  end
end

--- Değişen satırları kısa süre vurgula (ölçülü: tek renk, birkaç saniye).
function M.flash(buf, old_lines)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  local new_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  if #old_lines + #new_lines > 200000 then
    return
  end
  local a = table.concat(old_lines, "\n") .. "\n"
  local b = table.concat(new_lines, "\n") .. "\n"
  local ok, hunks = pcall(vim.text.diff, a, b, { result_type = "indices", algorithm = "histogram" })
  if not ok or type(hunks) ~= "table" then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hunks) do
    local start_b, count_b = h[3], h[4]
    for l = start_b, start_b + count_b - 1 do
      if l >= 1 and l <= #new_lines then
        pcall(api.nvim_buf_set_extmark, buf, ns, l - 1, 0, { line_hl_group = "NoctisFlash", priority = 5 })
      end
    end
  end
  vim.defer_fn(function()
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end, 4000)
end

local pending = {} ---@type table<integer, {lines:string[], views:table}>

---@param buf integer
function M.mark_conflict(buf, reason)
  vim.b[buf].noctis_conflict = { reason = reason, at = os.time() }
  api.nvim_exec_autocmds("User", { pattern = "NoctisConflict", modeline = false, data = { buf = buf, reason = reason } })
  vim.cmd("redrawstatus")
end

function M.clear_conflict(buf)
  if api.nvim_buf_is_valid(buf) and vim.b[buf].noctis_conflict then
    vim.b[buf].noctis_conflict = nil
    vim.cmd("redrawstatus")
  end
end

function M.has_conflict(buf)
  return api.nvim_buf_is_valid(buf) and vim.b[buf].noctis_conflict ~= nil
end

--- FileChangedShell işleyicisi (buffer değiştirilemez; yalnız karar verilir).
local function on_changed_shell(ev)
  local buf = ev.buf
  local reason = vim.v.fcs_reason
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":~:.")
  if reason == "deleted" then
    vim.v.fcs_choice = ""
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        -- İçerik artık yalnız bu buffer'da: çıkışta sorulması için değiştirilmiş say.
        vim.bo[buf].modified = true
        M.mark_conflict(buf, "deleted")
        U.warn(("`%s` diskten silindi veya taşındı. İçerik buffer'da korunuyor.\nKaydetmek: Space f s · Seçenekler: :NoctisConflict"):format(name))
      end
    end)
  elseif reason == "conflict" or (reason == "changed" and vim.bo[buf].modified) then
    vim.v.fcs_choice = ""
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        M.mark_conflict(buf, "changed")
        U.warn(
          ("`%s` dışarıdan değişti ama buffer'da kaydedilmemiş düzenlemeniz var.\nHiçbiri ezilmedi. Karşılaştır/birleştir: :NoctisConflict"):format(name)
        )
      end
    end)
  elseif reason == "changed" then
    pending[buf] = { lines = api.nvim_buf_get_lines(buf, 0, -1, false), views = views_for(buf) }
    vim.v.fcs_choice = "reload"
  else -- "mode", "time": içerik değişmedi
    vim.v.fcs_choice = ""
  end
end

local function on_changed_shell_post(ev)
  local buf = ev.buf
  local p = pending[buf]
  pending[buf] = nil
  M.clear_conflict(buf)
  M.remember(buf)
  if p then
    restore_views(buf, p.views)
    M.flash(buf, p.lines)
    api.nvim_exec_autocmds("User", { pattern = "NoctisBufReloaded", modeline = false, data = { buf = buf } })
  end
end

--- Belirli buffer(lar) için disk denetimi tetikle.
function M.check(buf)
  if buf then
    if is_file_buf(buf) then
      pcall(vim.cmd, "checktime " .. buf)
    end
  else
    pcall(vim.cmd, "checktime")
  end
end

--- Disk, buffer'ın son senkronundan beri değişti mi? (stat + içerik)
---@return boolean changed, string? reason  "changed" | "deleted"
function M.disk_changed(buf)
  local path = api.nvim_buf_get_name(buf)
  local st = vim.uv.fs_stat(path)
  local old = M.stat[buf]
  if not st then
    return old ~= nil, "deleted"
  end
  if not old then
    return false
  end
  if st.mtime.sec == old.mtime and st.mtime.nsec == old.nsec and st.size == old.size and st.ino == old.ino then
    return false
  end
  local base = M.base[buf]
  if base then
    local text = U.read_file(path)
    if text == base then
      -- yalnız zaman damgası/inode değişti (ör. atomik kayıt aynı içerikle)
      M.stat[buf] = { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino }
      return false
    end
  end
  return true, "changed"
end

--- Kullanıcı güncel disk sürümünü gördü/birleştirdi: bu sürüm yeni referanstır.
--- Sonraki kayıt, disk o andan beri yeniden değişmediyse Neovim'in yerleşik
--- "okunduktan sonra değişti" sorusunu sormadan yazar.
function M.acknowledge(buf)
  local st = vim.uv.fs_stat(api.nvim_buf_get_name(buf))
  M.stat[buf] = st and { mtime = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, ino = st.ino } or nil
  vim.b[buf].noctis_ack = true
end

--- Diskteki içerik (okunamazsa nil)
function M.disk_text(buf)
  return U.read_file(api.nvim_buf_get_name(buf))
end

local function to_lines(text, ff)
  if ff == "dos" then
    text = text:gsub("\r\n", "\n")
  end
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

--- Disk sürümünü salt-okunur scratch buffer olarak aç ve yerel buffer ile diff'le.
function M.diff_with_disk(buf)
  local text = M.disk_text(buf)
  if not text then
    U.warn("Diskte dosya yok; karşılaştırılacak sürüm bulunamadı.")
    return
  end
  local name = api.nvim_buf_get_name(buf)
  vim.cmd("tab split")
  api.nvim_win_set_buf(0, buf)
  vim.cmd("diffthis")
  vim.cmd("leftabove vnew")
  local scratch = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(scratch, 0, -1, false, to_lines(text, vim.bo[buf].fileformat))
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  pcall(api.nvim_buf_set_name, scratch, "disk://" .. vim.fn.fnamemodify(name, ":~:.") .. " (diskteki sürüm)")
  vim.cmd("diffthis")
  vim.wo.winbar = "%#NoctisWarning# DİSK %#NoctisMuted# güncel disk içeriği (salt okunur)"
  vim.cmd("wincmd l")
  vim.wo.winbar = "%#NoctisAccent# YEREL %#NoctisMuted# buffer'daki düzenlemeniz · `do`/`dp` ile hunk taşı · kaydet: Space f s"
  U.info("Sol: disk, sağ: yerel buffer. `]c`/`[c` ile farklar arasında gezin; sekmeyi kapatmak: :tabclose")
end

--- Yerel buffer içeriğini ayrı bir kopya dosyasına kaydet (proje dışında, state içinde).
function M.save_copy(buf)
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  local dir = U.state_dir("recovered")
  local path = ("%s/%s.%s.local"):format(dir, name, os.date("%Y%m%d-%H%M%S"))
  local ok, err = U.write_file(path, M.buf_text(buf), 384)
  if ok then
    U.info("Yerel sürümün kopyası kaydedildi:\n" .. path)
    return path
  end
  U.error("Kopya kaydedilemedi: " .. tostring(err))
end

--- 3 yollu birleştirme: taban (son senkron), yerel (buffer), disk.
--- Sonuç buffer'a yazılır (undo ile geri alınabilir); çakışan bölümler
--- işaretlerle bırakılır. Diske yazılmaz.
function M.merge(buf)
  local base = M.base[buf]
  local disk = M.disk_text(buf)
  if not base or not disk then
    U.warn("Güvenilir ortak taban yok; birleştirme yerine karşılaştırma açılıyor.")
    return M.diff_with_disk(buf)
  end
  if not U.has("git") then
    U.warn("Birleştirme için `git merge-file` gerekli; karşılaştırma açılıyor.")
    return M.diff_with_disk(buf)
  end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p", "0o700")
  local fl, fb, fd = tmp .. "/yerel", tmp .. "/taban", tmp .. "/disk"
  U.write_file(fl, M.buf_text(buf))
  U.write_file(fb, base)
  U.write_file(fd, disk)
  local res = vim
    .system({ "git", "merge-file", "-p", "-L", "yerel (buffer)", "-L", "taban (son senkron)", "-L", "disk (güncel)", fl, fb, fd }, { text = true })
    :wait(10000)
  vim.fn.delete(tmp, "rf")
  if res.code < 0 or res.code > 127 then
    U.error("Birleştirme başarısız: " .. (res.stderr or ""))
    return
  end
  local merged = to_lines(res.stdout or "", "unix")
  api.nvim_buf_set_lines(buf, 0, -1, false, merged)
  -- Birleşmiş içerik artık güncel disk sürümünü temel alır.
  M.base[buf] = disk
  M.acknowledge(buf)
  if res.code == 0 then
    M.clear_conflict(buf)
    U.info("Birleştirme temiz tamamlandı (buffer güncellendi, henüz kaydedilmedi). Geri almak: u")
  else
    vim.b[buf].noctis_conflict = { reason = "markers", at = os.time() }
    U.warn(("%d çakışan bölüm var: <<<<<<< / ||||||| / ======= / >>>>>>> işaretlerini düzenleyip kaydedin."):format(res.code))
    vim.fn.search("^<<<<<<< ", "w")
  end
  -- Neovim'in kayıtlı dosya zamanını güncelle ki kaydetme yeniden uyarmasın.
  pcall(vim.cmd, "checktime " .. buf)
end

--- Diskteki sürümü buffer'a yükle (yerel düzenlemenin kopyası önce saklanır).
function M.take_disk(buf)
  if vim.bo[buf].modified then
    M.save_copy(buf)
  end
  api.nvim_buf_call(buf, function()
    vim.cmd("edit!")
  end)
  M.clear_conflict(buf)
  M.remember(buf)
end

--- Çatışma çözüm menüsü
function M.resolve(buf, opts)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  opts = opts or {}
  local c = vim.b[buf].noctis_conflict
  local exists = vim.uv.fs_stat(api.nvim_buf_get_name(buf)) ~= nil
  local choices = {}
  if c and c.reason == "deleted" or not exists then
    choices = {
      { "Bu yola yeniden kaydet", function()
        api.nvim_buf_call(buf, function()
          vim.cmd("write!")
        end)
        M.clear_conflict(buf)
      end },
      { "Yeni konuma kaydet…", function()
        require("noctis.files").save_as(buf)
      end },
      { "Yerel içeriğin kopyasını sakla", function()
        M.save_copy(buf)
      end },
    }
  else
    choices = {
      { "Karşılaştır (disk ↔ yerel)", function()
        M.diff_with_disk(buf)
      end },
      { "3 yollu birleştir (taban: son senkron)", function()
        M.merge(buf)
      end },
      { "Yerel sürümü yaz (diskteki değişikliği ez)", function()
        M.save_copy_disk(buf)
        api.nvim_buf_call(buf, function()
          vim.cmd("write!")
        end)
        M.clear_conflict(buf)
        M.remember(buf)
      end },
      { "Diskteki sürümü yükle (yerel kopya önce saklanır)", function()
        M.take_disk(buf)
      end },
      { "Yerel içeriği ayrı dosyaya kopyala", function()
        M.save_copy(buf)
      end },
    }
  end
  local labels = vim.tbl_map(function(x)
    return x[1]
  end, choices)
  vim.ui.select(labels, {
    prompt = opts.on_save and "Disk sürümü kaydetmeden önce değişmiş — ne yapılsın?" or "Disk/buffer çatışması",
  }, function(_, idx)
    if idx then
      choices[idx][2]()
    end
  end)
end

--- Diskteki (ezilecek) sürümün kopyasını sakla — geri dönüş yolu.
function M.save_copy_disk(buf)
  local text = M.disk_text(buf)
  if not text then
    return
  end
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  local path = ("%s/%s.%s.disk"):format(U.state_dir("recovered"), name, os.date("%Y%m%d-%H%M%S"))
  U.write_file(path, text, 384)
  U.log("INFO", "ezilen disk sürümü saklandı: " .. path)
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_sync", { clear = true })
  api.nvim_create_autocmd("FileChangedShell", { group = group, callback = on_changed_shell })
  api.nvim_create_autocmd("FileChangedShellPost", { group = group, callback = on_changed_shell_post })
  api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      M.remember(ev.buf)
      if ev.event == "BufWritePost" then
        M.clear_conflict(ev.buf)
      end
    end,
  })
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      M.base[ev.buf], M.stat[ev.buf] = nil, nil
      pending[ev.buf] = nil
    end,
  })
  -- Kaçırılan değişiklikler: odak dönüşü, buffer'a giriş, terminalden çıkış.
  api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
        M.check(ev.event == "BufEnter" and ev.buf or nil)
      end
    end,
  })
  -- Diske yazmadan hemen önce son bir denetim: çatışma işaretliyse ve
  -- kullanıcı bunu NOCTIS kaydet komutuyla çözmediyse yerleşik koruma devrededir.
end

return M
