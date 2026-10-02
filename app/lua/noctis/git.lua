-- Git: dal bilgisi, değişen dosyalar, dosya diff'i. Lazygit isteğe bağlıdır;
-- yokken temel Git özeti ve diff işlevleri çalışır. Commit/push gibi işlemler
-- yalnız kullanıcı tarafından açıkça başlatılır (NOCTIS bunları kendisi yapmaz).
-- Git deposu olmayan klasörde tüm işlevler sessizce devre dışı kalır.
local M = {}

local U = require("noctis.util")
local api = vim.api

local cache = {} ---@type table<string, {branch?:string, at:integer}>

local function root()
  return require("noctis.project").root()
end

---@param r? string
---@return string? top
function M.toplevel(r)
  r = r or root()
  local res = vim.system({ "git", "-C", r, "rev-parse", "--show-toplevel" }, { text = true }):wait(3000)
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or "")
end

--- Statusline için önbellekli dal adı (asenkron yenilenir)
function M.cached_branch()
  local r = root()
  local c = cache[r]
  local now = vim.uv.now()
  if not c or now - c.at > 5000 then
    cache[r] = cache[r] or { at = now }
    cache[r].at = now
    if U.has("git") then
      vim.system({ "git", "-C", r, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(res)
        cache[r].branch = res.code == 0 and vim.trim(res.stdout or "") or nil
        vim.schedule(function()
          vim.cmd("redrawstatus")
        end)
      end)
    end
  end
  return cache[r] and cache[r].branch
end

---@return {path:string, x:string, y:string}[]?, string? branch_line
function M.status_entries(r)
  local res = vim.system({ "git", "-C", r, "status", "--porcelain=v1", "-b", "-z", "--untracked-files=all" }, { text = true }):wait(10000)
  if res.code ~= 0 then
    return nil
  end
  local items, branch = {}, nil
  local parts = vim.split(res.stdout or "", "\0", { plain = true })
  local i = 1
  while i <= #parts do
    local p = parts[i]
    if p:sub(1, 2) == "##" then
      branch = p:sub(4)
    elseif #p > 3 then
      local x, y, path = p:sub(1, 1), p:sub(2, 2), p:sub(4)
      items[#items + 1] = { x = x, y = y, path = path }
      if x == "R" or x == "C" then
        i = i + 1 -- yeniden adlandırmada eski ad ayrı alan olarak gelir
      end
    end
    i = i + 1
  end
  return items, branch
end

--- Yerel Git özeti (lazygit yokken)
function M.summary()
  local r = M.toplevel()
  if not r then
    U.info("Bu klasör bir Git deposu değil.")
    return
  end
  local items, branch = M.status_entries(r)
  if not items then
    U.error("git status çalıştırılamadı.")
    return
  end
  local staged, unstaged, untracked = {}, {}, {}
  for _, it in ipairs(items) do
    if it.x == "?" then
      untracked[#untracked + 1] = it
    else
      if it.x ~= " " then
        staged[#staged + 1] = it
      end
      if it.y ~= " " then
        unstaged[#unstaged + 1] = it
      end
    end
  end
  local lines, targets = {}, {}
  local function add(text, path)
    lines[#lines + 1] = text
    if path then
      targets[#lines] = path
    end
  end
  add("Git: " .. (branch or "?"))
  add("Depo: " .. vim.fn.fnamemodify(r, ":~"))
  add("")
  local function section(title, list, code)
    add(("%s (%d)"):format(title, #list))
    for _, it in ipairs(list) do
      add(("  %s  %s"):format(code(it), it.path), r .. "/" .. it.path)
    end
    add("")
  end
  section("Hazırlanmış (staged)", staged, function(it)
    return it.x
  end)
  section("Değiştirilmiş (unstaged)", unstaged, function(it)
    return it.y
  end)
  section("İzlenmeyen (untracked)", untracked, function()
    return "?"
  end)
  add("Enter: dosyayı aç · d: diff · q: kapat")
  if not U.has("lazygit") then
    add("Lazygit kurulu değil; ayrıntılı işlemler için kurabilirsiniz (isteğe bağlı).")
  end
  local buf, win = require("noctis.ui.float").text(lines, { title = "Git özeti", ft = "noctis-git", width = 90 })
  local function target()
    return targets[api.nvim_win_get_cursor(win)[1]]
  end
  vim.keymap.set("n", "<CR>", function()
    local t = target()
    if t then
      api.nvim_win_close(win, true)
      vim.cmd("edit " .. vim.fn.fnameescape(t))
    end
  end, { buffer = buf })
  vim.keymap.set("n", "d", function()
    local t = target()
    if t then
      api.nvim_win_close(win, true)
      vim.cmd("edit " .. vim.fn.fnameescape(t))
      M.diff_file()
    end
  end, { buffer = buf })
end

function M.view()
  local ok, Snacks = pcall(require, "snacks")
  if U.has("lazygit") and ok and Snacks.lazygit and M.toplevel() then
    return Snacks.lazygit({ cwd = M.toplevel() })
  end
  M.summary()
end

function M.status()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker and not U.is_safe_mode() then
    if not M.toplevel() then
      U.info("Bu klasör bir Git deposu değil.")
      return
    end
    return Snacks.picker.git_status({ cwd = M.toplevel() })
  end
  M.summary()
end

--- Dosya diff'i: sol = index (yoksa HEAD) sürümü, sağ = çalışma kopyası.
--- Index'e veya çalışma ağacına yazmaz.
function M.diff_file()
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    U.info("Diff için bir dosya açın.")
    return
  end
  local r = M.toplevel(vim.fn.fnamemodify(path, ":h"))
  if not r then
    U.info("Dosya bir Git deposunda değil.")
    return
  end
  local rel = U.relpath(r, path)
  local res = vim.system({ "git", "-C", r, "show", ":" .. rel }, { text = true }):wait(5000)
  local label = "index"
  if res.code ~= 0 then
    res = vim.system({ "git", "-C", r, "show", "HEAD:" .. rel }, { text = true }):wait(5000)
    label = "HEAD"
  end
  if res.code ~= 0 then
    U.info("Dosya Git'te izlenmiyor (yeni dosya); karşılaştırılacak sürüm yok.")
    return
  end
  local text = res.stdout or ""
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  for i, l in ipairs(lines) do
    lines[i] = l:gsub("\r$", "")
  end
  vim.cmd("tab split")
  vim.cmd("diffthis")
  vim.wo.winbar = "%#NoctisAccent# ÇALIŞMA KOPYASI %#NoctisMuted# " .. rel
  vim.cmd("leftabove vnew")
  local scratch = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  vim.cmd("diffthis")
  vim.wo.winbar = ("%%#NoctisWarning# GIT %s %%#NoctisMuted# salt okunur · ]c/[c: farklar · :tabclose"):format(label:upper())
  vim.cmd("wincmd l")
end

function M.reset_hunk()
  if vim.fn.confirm("İmleçteki Git hunk'ı index sürümüne döndürülsün mü? (u ile geri alınabilir)", "&Evet\n&Hayır", 2) == 1 then
    require("gitsigns").reset_hunk()
  end
end

return M
