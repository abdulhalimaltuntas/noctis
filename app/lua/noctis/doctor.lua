-- `noctis --doctor` ve `:checkhealth noctis` için ortak denetimler.
-- Eklentilere bağımlı değildir (eksik eklentiyi raporlamak için onu yüklemez),
-- ağ isteği yapmaz, AI görevi başlatmaz ve hesap bilgisi göstermez.
-- Doğrudan çalıştırma: NVIM_APPNAME=noctis nvim --headless -l .../doctor.lua
local M = {}

local function has(exe)
  return vim.fn.executable(exe) == 1
end

local function run(cmd, timeout)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(timeout or 5000)
  end)
  if not ok or not res then
    return nil
  end
  return res
end

local function first_line(s)
  return vim.trim((s or ""):match("[^\n]*") or "")
end

---@class noctis.DoctorItem
---@field level "ok"|"warn"|"error"|"info"
---@field msg string
---@field advice? string

---@return {title:string, items:noctis.DoctorItem[]}[]
function M.checks()
  local sections = {}
  local cur
  local function section(title)
    cur = { title = title, items = {} }
    sections[#sections + 1] = cur
  end
  local function add(level, msg, advice)
    cur.items[#cur.items + 1] = { level = level, msg = msg, advice = advice }
  end

  local brand = require("noctis.brand")
  -- ── Çekirdek ───────────────────────────────────────────────────────────
  section("Çekirdek")
  local v = vim.version()
  local vs = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-" .. brand.min_nvim) == 1 then
    add("ok", ("Neovim %s (%s)"):format(vs, vim.v.progpath))
  else
    add("error", ("Neovim %s çok eski; en az %s gerekli"):format(vs, brand.min_nvim), "https://github.com/neovim/neovim/releases")
  end
  add("ok", ("%s %s · uygulama: %s"):format(brand.name, brand.version, brand.home))
  add("info", ("NVIM_APPNAME=%s (normal Neovim yapılandırmanızdan ayrı)"):format(vim.env.NVIM_APPNAME or "?"))
  add("info", "config: " .. vim.fn.stdpath("config"))
  add("info", "data:   " .. vim.fn.stdpath("data"))
  add("info", "state:  " .. vim.fn.stdpath("state") .. "  (oturumlar, undo, AI kayıtları, log)")
  add("info", "cache:  " .. vim.fn.stdpath("cache"))

  -- ── Kullanıcı ayarları ────────────────────────────────────────────────
  section("Kullanıcı ayarları")
  local cfg = require("noctis.config")
  cfg.load()
  if vim.uv.fs_stat(cfg.path) then
    add("ok", "config.lua bulundu: " .. cfg.path)
  else
    add("info", "config.lua yok; varsayılanlar kullanılıyor (örnek: " .. brand.home .. "/examples/config.lua)")
  end
  for _, e in ipairs(cfg.errors) do
    add("error", e, "Hatalı değer yerine varsayılan kullanılır; dosyayı düzeltin.")
  end
  for _, w in ipairs(cfg.warnings) do
    add("warn", w)
  end
  if #cfg.errors == 0 and #cfg.warnings == 0 and vim.uv.fs_stat(cfg.path) then
    add("ok", "Ayarlar geçerli")
  end

  -- ── Eklentiler ─────────────────────────────────────────────────────────
  section("Eklentiler (kilit dosyasına göre)")
  local lockfile = brand.home .. "/lazy-lock.json"
  local lock = require("noctis.util").json_read(lockfile)
  local root = vim.fn.stdpath("data") .. "/lazy"
  if not lock then
    add("error", "lazy-lock.json okunamadı: " .. lockfile)
  else
    local names = vim.tbl_keys(lock)
    table.sort(names)
    local missing, drift = 0, 0
    for _, name in ipairs(names) do
      local dir = root .. "/" .. name
      if not vim.uv.fs_stat(dir) then
        missing = missing + 1
        add("warn", name .. ": kurulu değil")
      else
        local res = has("git") and run({ "git", "-C", dir, "rev-parse", "HEAD" })
        local head = res and res.code == 0 and first_line(res.stdout) or nil
        if head and head ~= lock[name].commit then
          drift = drift + 1
          add("warn", ("%s: kilitten farklı commit (%s ≠ %s)"):format(name, head:sub(1, 7), lock[name].commit:sub(1, 7)), "Kilit dosyasına dönmek için NOCTIS içinde :Lazy restore")
        end
      end
    end
    if missing == #names then
      add("error", "Eklentiler kurulmamış. Editör temel modda açılır.", brand.command .. " --setup (ağ gerekir)")
    elseif missing > 0 then
      add("warn", missing .. " eklenti eksik", brand.command .. " --setup")
    else
      add("ok", ("%d eklenti kurulu%s"):format(#names, drift == 0 and ", kilit dosyasıyla uyumlu" or ""))
    end
  end

  -- ── Araçlar ────────────────────────────────────────────────────────────
  section("Harici araçlar")
  local tools = {
    { "git", "error", "Git özeti/diff, eklenti kurulumu ve birleştirme için gerekli" },
    { "rg", "error", "Projede metin arama, toplu değiştirme ve AI kapsam taraması için gerekli (ripgrep)" },
    { "fd", "info", "İsteğe bağlı; yoksa ripgrep kullanılır" },
    { "lazygit", "info", "İsteğe bağlı Git arayüzü; yoksa NOCTIS Git özeti kullanılır" },
    { "tree-sitter", "info", "Tree-sitter parser derlemek için (isteğe bağlı; yoksa Vim söz dizimi)" },
  }
  for _, t in ipairs(tools) do
    if has(t[1]) then
      add("ok", ("%s: %s"):format(t[1], vim.fn.exepath(t[1])))
    else
      add(t[2], ("%s bulunamadı — %s"):format(t[1], t[3]))
    end
  end
  if not (has("cc") or has("gcc") or has("clang")) then
    add("info", "C derleyicisi yok — Tree-sitter parser kurulamaz (isteğe bağlı)")
  end

  -- ── Terminal ve görünüm ───────────────────────────────────────────────
  section("Terminal ve görünüm")
  local term, colorterm = vim.env.TERM or "?", vim.env.COLORTERM or ""
  add("info", ("TERM=%s COLORTERM=%s"):format(term, colorterm ~= "" and colorterm or "(boş)"))
  if colorterm == "truecolor" or colorterm == "24bit" then
    add("ok", "Truecolor bildirildi")
  else
    add("warn", "Truecolor bildirilmedi; Neovim açılışta terminali sorgular. Desteklenmiyorsa 256 renk yedeği kullanılır.", "config.lua: truecolor = true | false ile zorlanabilir")
  end
  if term == "linux" then
    add("warn", "Linux konsolu: ikonlar ve yuvarlatılmış kenarlıklar otomatik olarak sade karakterlere döner")
  end
  add("info", ("İkonlar: %s (Nerd Font varlığı güvenilir şekilde algılanamaz; görünmüyorsa icons = false)"):format(cfg.options.icons and "açık" or "kapalı"))

  -- ── Clipboard ──────────────────────────────────────────────────────────
  section("Sistem panosu")
  if cfg.options.clipboard == "internal" then
    add("info", "Ayar gereği yalnız NOCTIS içi kayıtlar kullanılıyor")
  elseif vim.fn.has("clipboard") == 1 then
    local ok, name = pcall(vim.fn["provider#clipboard#Executable"])
    add("ok", "Pano sağlayıcısı: " .. ((ok and name ~= "") and name or "var"))
  else
    add("warn", "Sistem panosu kullanılamıyor; kopyalanan metin NOCTIS içi kayıtlarda kalır", "Linux: wl-clipboard (Wayland) veya xclip/xsel (X11) kurun. SSH'de OSC 52 destekleyen terminal kullanın.")
  end

  -- ── Dil paketleri ──────────────────────────────────────────────────────
  section("Dil paketleri")
  local lang = require("noctis.lang")
  lang.setup_path()
  for _, name in ipairs(lang.enabled()) do
    local p, st = lang.packs[name], lang.status(name)
    local parts, missing = {}, {}
    for _, s in ipairs(p.servers) do
      if st.server[s.name] then
        parts[#parts + 1] = s.exe
      else
        missing[#missing + 1] = s.exe .. " (" .. s.hint .. ")"
      end
    end
    for _, f in ipairs(p.formatters) do
      if st.formatter[f.name] then
        parts[#parts + 1] = f.exe
      else
        missing[#missing + 1] = f.exe .. " (" .. f.hint .. ")"
      end
    end
    local np = 0
    for _, ok in pairs(st.parser) do
      if ok then
        np = np + 1
      end
    end
    local ptxt = ("parser %d/%d"):format(np, #p.parsers)
    if #missing == 0 then
      add("ok", ("%s: %s · %s"):format(p.label, table.concat(parts, ", "), ptxt))
    else
      add("info", ("%s: eksik → %s · %s"):format(p.label, table.concat(missing, "; "), ptxt), "NOCTIS içinde :NoctisLang install " .. name)
    end
  end

  -- ── PTY ve dosya izleme ───────────────────────────────────────────────
  section("PTY ve dosya izleme")
  local okpty, job = pcall(vim.fn.jobstart, { "sh", "-c", "exit 0" }, { pty = true })
  if okpty and job and job > 0 then
    local code = vim.fn.jobwait({ job }, 3000)[1]
    if code == 0 then
      add("ok", "PTY oluşturulabiliyor (gerçek terminal oturumları)")
    else
      add("warn", "PTY süreci beklenen şekilde bitmedi (kod " .. tostring(code) .. ")")
    end
  else
    add("error", "PTY oluşturulamadı: " .. tostring(job), "AI ve terminal panelleri çalışmaz")
  end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local h = vim.uv.new_fs_event()
  local seen = false
  local started = h and h:start(tmp, {}, function()
    seen = true
  end)
  if started then
    vim.fn.writefile({ "x" }, tmp .. "/probe")
    vim.wait(1000, function()
      return seen
    end, 20)
    h:stop()
    h:close()
    if seen then
      add("ok", "Dosya izleme olayları alınıyor (dizin başına izleme)")
    else
      add("warn", "Dosya izleme olayı gelmedi; değişiklikler periyodik taramayla izlenir (gecikmeli)")
    end
  else
    add("warn", "Dosya izleyici başlatılamadı; periyodik tarama kullanılır")
  end
  vim.fn.delete(tmp, "rf")
  local mw = io.open("/proc/sys/fs/inotify/max_user_watches", "r")
  if mw then
    local n = tonumber(mw:read("*l"))
    mw:close()
    local need = cfg.options.ai.watch.max_dirs
    if n and n < need then
      add("warn", ("inotify izleme kotası düşük (%d < %d)"):format(n, need), "sudo sysctl fs.inotify.max_user_watches=524288")
    elseif n then
      add("ok", ("inotify izleme kotası: %d"):format(n))
    end
  end

  -- ── AI profilleri ─────────────────────────────────────────────────────
  section("AI profilleri (görev başlatılmaz; yalnız --version sorgulanır)")
  local P = require("noctis.ai.profiles")
  local all, order, errors = P.all()
  for _, e in ipairs(errors) do
    add("error", e)
  end
  for _, name in ipairs(order) do
    local p = all[name]
    local exe = P.resolve(p)
    if not exe then
      add("info", ("%s: `%s` bulunamadı"):format(p.label, p.cmd[1]), "Kurulum: " .. (p.install or "aracın belgeleri"))
    else
      local ver
      if p.version_args then
        local cmd = { exe }
        vim.list_extend(cmd, p.version_args)
        local res = run(cmd, 8000)
        if res and res.code == 0 then
          ver = first_line(res.stdout ~= "" and res.stdout or res.stderr)
        else
          ver = "sürüm okunamadı"
        end
      end
      add("ok", ("%s: %s%s"):format(p.label, exe, ver and (" · " .. ver) or ""))
    end
  end
  return sections
end

local symbols = {
  ok = { "✓", "32" },
  warn = { "!", "33" },
  error = { "✗", "31" },
  info = { "·", "36" },
}

--- Terminal çıktısı (noctis --doctor)
function M.main()
  local color = vim.env.NO_COLOR == nil
  local out = io.stdout
  local function paint(code, s)
    return color and ("\27[" .. code .. "m" .. s .. "\27[0m") or s
  end
  local counts = { ok = 0, warn = 0, error = 0, info = 0 }
  local brand = require("noctis.brand")
  out:write(paint("1;35", brand.name .. " doctor") .. "\n")
  for _, sec in ipairs(M.checks()) do
    out:write("\n" .. paint("1;36", sec.title) .. "\n")
    for _, it in ipairs(sec.items) do
      counts[it.level] = counts[it.level] + 1
      local sym = symbols[it.level]
      out:write(("  %s %s\n"):format(paint(sym[2], sym[1]), it.msg))
      if it.advice then
        out:write(("      %s %s\n"):format(paint("2", "→"), it.advice))
      end
    end
  end
  out:write(("\nÖzet: %d tamam, %d uyarı, %d hata\n"):format(counts.ok, counts.warn, counts.error))
  out:flush()
  os.exit(counts.error > 0 and 1 or 0)
end

-- `nvim -l doctor.lua` ile çalıştırıldıysa
if _G.arg and type(_G.arg[0]) == "string" and _G.arg[0]:match("doctor%.lua$") then
  local home = vim.env.NOCTIS_HOME or vim.fn.fnamemodify(_G.arg[0], ":p:h:h:h")
  vim.env.NOCTIS_HOME = home
  package.path = home .. "/lua/?.lua;" .. home .. "/lua/?/init.lua;" .. package.path
  vim.opt.rtp:prepend(home)
  M.main()
end

return M
