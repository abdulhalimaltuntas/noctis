-- AI Workbench genel API'si (komutlar buradan çağrılır).
--
-- Ayrım: oturum/süreç yönetimi (sessions) ile dosya değişikliği tespiti
-- (tracker/watcher/baseline) birbirinden bağımsızdır; herhangi bir dış araç
-- dosyayı değiştirdiğinde de takip çalışır. NOCTIS açılışı hiçbir AI aracını
-- kendiliğinden başlatmaz.
local M = {}

local U = require("noctis.util")
local api = vim.api

local function sessions()
  return require("noctis.ai.sessions")
end
local function wb()
  return require("noctis.ai.workbench")
end
local function tracker()
  return require("noctis.ai.tracker")
end

--- Workbench'in gösterdiği proje kökü: etkin oturumun kökü, yoksa aktif proje.
function M.view_root()
  local s = package.loaded["noctis.ai.workbench"] and wb().current_session()
  if s then
    return s.root
  end
  return require("noctis.ai.review").root or require("noctis.project").root()
end

function M.toggle()
  require("noctis.ai.review").set_root(M.view_root())
  wb().toggle()
end

function M.hide()
  if package.loaded["noctis.ai.workbench"] then
    wb().hide()
  end
end

function M.focus()
  wb().open({ focus = true })
end

local function install_help(p)
  local lines = {
    ("# %s bulunamadı"):format(p.label),
    "",
    ("Aranan komut: %s"):format(p.cmd[1]),
    "",
    "Kurulum (resmi belgelerdeki yöntem):",
    "  " .. (p.install or "aracın belgelerine bakın"),
    "",
    "Belgeler: " .. (p.docs or "-"),
    "",
    "Farklı bir konumdaysa config.lua içinde yolu belirtin:",
    ("  ai = { profiles = { %s = { cmd = { \"/tam/yol/%s\" } } } }"):format(p.name, p.cmd[1]),
    "",
    "Hesap girişi ve izinler aracın kendi arayüzünde yapılır; NOCTIS anahtar saklamaz.",
  }
  require("noctis.ui.float").text(lines, { title = p.label, ft = "markdown" })
end

---@param opts? {resume?:boolean, profile?:string}
function M.new_session(opts)
  opts = opts or {}
  local P = require("noctis.ai.profiles")
  local all, order, errors = P.all()
  for _, e in ipairs(errors) do
    U.error("AI profili: " .. e)
  end
  local items = {}
  for _, name in ipairs(order) do
    local p = all[name]
    if not opts.resume or p.resume_args then
      items[#items + 1] = { p = p, exe = P.resolve(p) }
    end
  end
  if #items == 0 then
    U.warn("Uygun AI profili yok.")
    return
  end
  local function go(item)
    if not item.exe then
      return install_help(item.p)
    end
    M.start(item.p, opts)
  end
  if opts.profile then
    for _, it in ipairs(items) do
      if it.p.name == opts.profile then
        return go(it)
      end
    end
  end
  vim.ui.select(items, {
    prompt = opts.resume and "Önceki oturumuna devam edilecek araç" or "AI aracı seç",
    format_item = function(it)
      local where = it.exe and vim.fn.fnamemodify(it.exe, ":~") or "bulunamadı — kurulum yardımı"
      return ("%-14s %s"):format(it.p.label, where)
    end,
  }, function(it)
    if it then
      go(it)
    end
  end)
end

--- Başlangıç kaydı tamamlandıktan sonra aracı başlat.
function M.start(profile, opts)
  opts = opts or {}
  local root = require("noctis.project").root()
  if root == vim.env.HOME or root == "/" then
    if vim.fn.confirm(("Proje kökü %s. AI aracını burada başlatmak geniş bir kapsam demek; yine de devam edilsin mi?"):format(root), "&Evet\n&Hayır", 2) ~= 1 then
      return
    end
  end
  local others = sessions().running(root)
  if #others > 0 then
    local names = table.concat(
      vim.tbl_map(function(s)
        return s.label
      end, others),
      ", "
    )
    local msg = ("Bu projede çalışan AI oturumu var: %s.\nAynı çalışma ağacında eşzamanlı yazma riski vardır; değişiklikler araçlara göre ayrıştırılamaz.\nYine de başlatılsın mı?"):format(names)
    if vim.fn.confirm(msg, "&Başlat\n&Vazgeç", 2) ~= 1 then
      return
    end
  end
  require("noctis.ai.review").set_root(root)
  tracker().ensure(root, function()
    local win = wb().prepare_window()
    local s, err = sessions().start(profile, root, win, { resume = opts.resume })
    if not s then
      U.error(err or "başlatılamadı")
      wb().show_view("changes", false)
      return
    end
    if err then
      U.error(err)
    end
    wb().show_view(s.id, true)
  end)
end

function M.switch()
  local list = sessions().list
  local items = { { id = "changes", label = "Değişiklikler (inceleme aralığı)" } }
  for _, s in ipairs(list) do
    items[#items + 1] = { id = s.id, label = ("%d  %s  · %s  · %s"):format(s.n, s.label, sessions().status_text(s), vim.fn.fnamemodify(s.root, ":~")) }
  end
  vim.ui.select(items, {
    prompt = "AI görünümü",
    format_item = function(it)
      return it.label
    end,
  }, function(it)
    if it then
      if it.id ~= "changes" then
        require("noctis.ai.review").set_root(sessions().get(it.id).root)
      end
      wb().show_view(it.id, it.id ~= "changes")
    end
  end)
end

function M.review()
  local root = M.view_root()
  require("noctis.ai.review").set_root(root)
  local t = tracker().get(root)
  if not t then
    -- Kayıtlı etkin aralık varsa yükle; yoksa yeni başlangıç almadan bilgi ver
    if require("noctis.ai.store").active_id(root) then
      return tracker().ensure(root, function()
        wb().show_view("changes", true)
      end)
    end
  end
  wb().show_view("changes", true)
end

function M.new_interval()
  local root = M.view_root()
  local t = tracker().get(root)
  local msg = t
      and ("Etkin inceleme aralığı kapatılıp yeni başlangıç kaydı alınsın mı?\nDosyalar değiştirilmez; mevcut %d değişiklik yeni aralıkta görünmez (eski kayıt saklama süresi boyunca durur)."):format(vim.tbl_count(t.changes))
    or "Bu proje için yeni bir başlangıç kaydı alınsın mı? (dosyalar değiştirilmez)"
  if vim.fn.confirm(msg, "&Evet\n&Hayır", 2) ~= 1 then
    return
  end
  require("noctis.ai.review").set_root(root)
  tracker().new_interval(root, function()
    if wb().is_visible() then
      wb().refresh()
    end
  end)
end

local function pick_session(filter, cb)
  local cur = package.loaded["noctis.ai.workbench"] and wb().current_session()
  if cur and filter(cur) then
    return cb(cur)
  end
  local list = vim.tbl_filter(filter, sessions().list)
  if #list == 0 then
    U.info("Uygun AI oturumu yok.")
    return
  elseif #list == 1 then
    return cb(list[1])
  end
  vim.ui.select(list, {
    prompt = "AI oturumu",
    format_item = function(s)
      return ("%d  %s · %s"):format(s.n, s.label, sessions().status_text(s))
    end,
  }, function(s)
    if s then
      cb(s)
    end
  end)
end

function M.stop()
  pick_session(sessions().alive, function(s)
    if vim.fn.confirm(("%s oturumu durdurulsun mu? Süreç sonlandırılır."):format(s.label), "&Durdur\n&Vazgeç", 2) == 1 then
      sessions().stop(s)
    end
  end)
end

function M.restart()
  pick_session(function()
    return true
  end, function(s)
    if sessions().alive(s) then
      if vim.fn.confirm(("%s çalışıyor. Durdurulup yeniden başlatılsın mı?"):format(s.label), "&Evet\n&Hayır", 2) ~= 1 then
        return
      end
    end
    local profile = require("noctis.ai.profiles").get(s.profile)
    if not profile then
      U.error("Profil artık tanımlı değil: " .. s.profile)
      return
    end
    local root = s.root
    sessions().remove(s)
    local win = wb().prepare_window()
    local ns, err = sessions().start(profile, root, win, {})
    if ns then
      wb().show_view(ns.id, true)
    else
      U.error(err or "başlatılamadı")
    end
  end)
end

function M.scope_info()
  local root = M.view_root()
  local t = tracker().get(root)
  if not t then
    U.info("Bu proje için etkin inceleme aralığı yok (Space a n ile oturum başlatın).")
    return
  end
  local iv = t.interval
  local by_reason = {}
  for rel, e in pairs(iv.files) do
    if e.reason then
      by_reason[e.reason] = by_reason[e.reason] or {}
      table.insert(by_reason[e.reason], rel)
    end
  end
  local labels = {
    large = "Büyük dosyalar (içerik yok, yalnız boyut/zaman izlenir)",
    sensitive = "Hassas dosyalar (içerik asla kopyalanmaz)",
    limit = "Kayıt sınırını aşanlar (içerik yok)",
    excluded = "Kullanıcı dışlamaları",
    symlink = "Sembolik bağlantılar (izlenmez)",
    unreadable = "Okunamayanlar",
  }
  local s = iv.stats or {}
  local cfg = require("noctis.config").options.ai
  local lines = {
    "# İnceleme kapsamı",
    "",
    ("Proje: %s"):format(vim.fn.fnamemodify(root, ":~")),
    ("Başlangıç: %s · yöntem: %s"):format(os.date("%Y-%m-%d %H:%M:%S", iv.created_at), iv.method or "?"),
    ("İçeriği kaydedilen: %d dosya (%s) · kapsam dışı: %d · süre: %d ms"):format(s.captured or 0, U.human_size(s.bytes or 0), s.skipped or 0, s.ms or 0),
    s.limit_hit and ("Sınır: " .. s.limit_hit) or "Sınırlar aşılmadı.",
    ("Sınırlar: dosya başına %s · toplam %s · en çok %d dosya"):format(U.human_size(cfg.baseline.max_file_size), U.human_size(cfg.baseline.max_total_size), cfg.baseline.max_files),
    ("İzlenen dizin: %d%s"):format(t.watcher:count(), t.watcher.overflow and " (sınır aşıldı; kalanlar periyodik taranır)" or ""),
    "Hiç izlenmeyen klasörler: " .. table.concat(vim.tbl_keys(require("noctis.ai.scope").skip_dirs), ", "),
    ("Kayıt deposu: %s (saklama %d gün, en çok %d MB)"):format(require("noctis.ai.store").dir(root), cfg.retention_days, cfg.max_store_mb),
    "",
  }
  for reason, label in pairs(labels) do
    local list = by_reason[reason]
    if list then
      table.sort(list)
      lines[#lines + 1] = ("## %s (%d)"):format(label, #list)
      for i = 1, math.min(#list, 25) do
        lines[#lines + 1] = "  " .. list[i]
      end
      if #list > 25 then
        lines[#lines + 1] = ("  … ve %d dosya daha"):format(#list - 25)
      end
      lines[#lines + 1] = ""
    end
  end
  lines[#lines + 1] = "Kapsam dışı dosyalar değişirse listede görünür ama önceki içerikleri olmadığı için geri alınamaz."
  require("noctis.ui.float").text(lines, { title = "İnceleme kapsamı", ft = "markdown", width = 100 })
end

--- Seçili kodu AI'a bağlam olarak hazırla: önce gösterilir, onaysız gönderilmez.
function M.send_context()
  local mode = vim.fn.mode()
  local s_line, e_line
  if mode == "v" or mode == "V" or mode == "\22" then
    s_line, e_line = vim.fn.line("v"), vim.fn.line(".")
    if s_line > e_line then
      s_line, e_line = e_line, s_line
    end
    vim.cmd("normal! \27")
  else
    s_line, e_line = vim.fn.line("."), vim.fn.line(".")
  end
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  local rel = U.relpath(require("noctis.project").root(), path) or vim.fn.fnamemodify(path, ":~")
  local code = api.nvim_buf_get_lines(buf, s_line - 1, e_line, false)
  local text = ("%s:%d-%d\n```%s\n%s\n```\n"):format(rel, s_line, e_line, vim.bo[buf].filetype, table.concat(code, "\n"))
  pick_session(sessions().alive, function(s)
    local preview = vim.split(text, "\n", { plain = true })
    table.insert(preview, 1, ("Hedef: %s (%s). Enter: aracın giriş satırına yapıştır (gönderilmez) · q: vazgeç"):format(s.label, vim.fn.fnamemodify(s.root, ":~")))
    table.insert(preview, 2, "")
    local pbuf, pwin = require("noctis.ui.float").text(preview, { title = "Bağlam önizleme", ft = "markdown", footer = " Enter: yapıştır · q: vazgeç " })
    vim.keymap.set("n", "<CR>", function()
      api.nvim_win_close(pwin, true)
      if sessions().paste(s, text) then
        U.info("Bağlam aracın giriş satırına yapıştırıldı. Göndermek için aracın içinde Enter'a basın.")
        wb().show_view(s.id, true)
      end
    end, { buffer = pbuf })
  end)
end

--- Statusline özeti
function M.status_text()
  if not package.loaded["noctis.ai.sessions"] and not package.loaded["noctis.ai.tracker"] then
    return ""
  end
  local root = require("noctis.project").root()
  local parts = {}
  local ic = require("noctis.ui.icons").get().ui.ai
  local live = package.loaded["noctis.ai.sessions"] and sessions().running() or {}
  if #live == 1 then
    parts[#parts + 1] = live[1].label .. " " .. live[1].status
  elseif #live > 1 then
    parts[#parts + 1] = #live .. " oturum"
  end
  local t = package.loaded["noctis.ai.tracker"] and tracker().get(root)
  if t then
    local n = vim.tbl_count(t.changes)
    if n > 0 then
      parts[#parts + 1] = n .. " değişiklik"
    end
  end
  if #parts == 0 then
    return ""
  end
  return vim.trim(ic) .. " " .. table.concat(parts, " · ")
end

--- Gezgin işareti: aralıkta değişen dosyalar
function M.explorer_mark(path)
  if not path or not package.loaded["noctis.ai.tracker"] then
    return nil
  end
  for root, t in pairs(tracker().by_root) do
    local rel = U.relpath(root, path)
    if rel and t.changes[rel] then
      local k = t.changes[rel].kind
      return {
        text = ({ added = "A", modified = "M", deleted = "D" })[k],
        hl = ({ added = "NoctisChangeAdded", modified = "NoctisChangeModified", deleted = "NoctisChangeDeleted" })[k],
      }
    end
  end
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_ai", { clear = true })
  -- Önceden başlatılmış (kullanıcı eylemiyle) etkin aralık varsa takibi sürdür.
  -- Bu bir AI aracı başlatmaz.
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.defer_fn(function()
        local root = require("noctis.project").root()
        local ok, store = pcall(require, "noctis.ai.store")
        if ok and vim.uv.fs_stat(store.path(root) .. "/active.json") then
          local id = store.active_id(root)
          local iv = id and store.load_interval(root, id)
          if iv and not iv.closed_at then
            tracker().ensure(root, function() end)
            require("noctis.ai.review").set_root(root)
          end
        end
      end, 1500)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NoctisAIChanges",
    callback = function()
      -- Gezgin işaretlerini yenile
      local ok, explorer = pcall(require, "noctis.explorer")
      local p = ok and explorer.get()
      if p then
        pcall(function()
          require("snacks.explorer.actions").update(p, { refresh = true })
        end)
      end
    end,
  })
end

return M
