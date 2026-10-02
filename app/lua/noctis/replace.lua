-- Projede bul ve değiştir. Uygulamadan önce kapsam ve tüm değişiklikler
-- önizlemede gösterilir; satırlar tek tek hariç tutulabilir.
-- Önizleme ve uygulama aynı motoru (ripgrep --replace) kullanır; uygulama
-- sırasında her satırın hâlâ önizlenen orijinal metinle aynı olduğu
-- doğrulanır, değilse o satır atlanır. Satır sonu biçimi (CRLF) korunur.
local M = {}

local U = require("noctis.util")
local api = vim.api
local ns = api.nvim_create_namespace("noctis.replace")

M.MAX = 5000

local function rg_lines(args, r)
  local res = vim.system(args, { cwd = r, text = true }):wait(60000)
  if res.code ~= 0 and res.code ~= 1 then
    return nil, vim.trim(res.stderr or "ripgrep hatası")
  end
  local out = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local path, rest = line:match("^(.-)%z(.*)$")
    if path then
      local lnum, text = rest:match("^(%d+):(.*)$")
      if lnum then
        out[#out + 1] = { path = path, lnum = tonumber(lnum), text = text }
      end
    end
  end
  return out
end

---@param q {pattern:string, replacement:string, regex:boolean, glob?:string}
function M.collect(q, r)
  local base = { "rg", "--no-heading", "--with-filename", "--line-number", "--null", "--sort", "path", "--color", "never" }
  if not q.regex then
    base[#base + 1] = "--fixed-strings"
  end
  if q.glob and q.glob ~= "" then
    base[#base + 1] = "--glob"
    base[#base + 1] = q.glob
  end
  local orig_args = vim.list_extend(vim.deepcopy(base), { "--", q.pattern })
  local repl_args = vim.list_extend(vim.deepcopy(base), { "--replace", q.replacement, "--", q.pattern })
  local orig, err = rg_lines(orig_args, r)
  if not orig then
    return nil, err
  end
  local repl, err2 = rg_lines(repl_args, r)
  if not repl then
    return nil, err2
  end
  if #orig ~= #repl then
    return nil, "eşleşme sayıları tutarsız (dosyalar arama sırasında değişmiş olabilir); tekrar deneyin"
  end
  local changes = {}
  for i, o in ipairs(orig) do
    local n = repl[i]
    if n.path == o.path and n.lnum == o.lnum and n.text ~= o.text then
      changes[#changes + 1] = { path = U.norm(r .. "/" .. o.path:gsub("^%./", "")), rel = o.path:gsub("^%./", ""), lnum = o.lnum, old = o.text, new = n.text, on = true }
    end
  end
  return changes
end

local function apply_file(path, list)
  local applied, skipped = 0, 0
  local buf = vim.fn.bufnr(path)
  if buf > 0 and api.nvim_buf_is_loaded(buf) then
    local was_modified = vim.bo[buf].modified
    local dos = vim.bo[buf].fileformat == "dos"
    for _, c in ipairs(list) do
      local cur = api.nvim_buf_get_lines(buf, c.lnum - 1, c.lnum, false)[1]
      local old = dos and c.old:gsub("\r$", "") or c.old
      local new = dos and c.new:gsub("\r$", "") or c.new
      if cur == old then
        api.nvim_buf_set_lines(buf, c.lnum - 1, c.lnum, false, { new })
        applied = applied + 1
      else
        skipped = skipped + 1
      end
    end
    -- Temiz buffer'lar diske yazılır (diğer dosyalarla tutarlı); kaydedilmemiş
    -- düzenlemesi olan buffer yalnız güncellenir, kaydetme kullanıcıda kalır.
    if not was_modified and applied > 0 and not require("noctis.sync").disk_changed(buf) then
      api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
    end
    return applied, skipped
  end
  local text = U.read_file(path)
  if not text then
    return 0, #list
  end
  local lines = vim.split(text, "\n", { plain = true })
  for _, c in ipairs(list) do
    if lines[c.lnum] == c.old then
      lines[c.lnum] = c.new
      applied = applied + 1
    else
      skipped = skipped + 1
    end
  end
  if applied > 0 then
    local st = vim.uv.fs_stat(path)
    local ok, err = U.write_file(path, table.concat(lines, "\n"), st and st.mode % 4096 or 420)
    if not ok then
      U.error("Yazılamadı: " .. path .. " — " .. tostring(err))
      return 0, #list
    end
  end
  return applied, skipped
end

function M.apply(changes)
  local by_file, order = {}, {}
  for _, c in ipairs(changes) do
    if c.on then
      if not by_file[c.path] then
        by_file[c.path] = {}
        order[#order + 1] = c.path
      end
      table.insert(by_file[c.path], c)
    end
  end
  local total, skipped = 0, 0
  for _, path in ipairs(order) do
    local a, s = apply_file(path, by_file[path])
    total, skipped = total + a, skipped + s
  end
  if skipped > 0 then
    U.warn(("%d değişiklik uygulandı, %d satır atlandı (önizlemeden sonra değişmiş)."):format(total, skipped))
  else
    U.info(("%d değişiklik %d dosyaya uygulandı. Açık buffer'larda u ile geri alınabilir."):format(total, #order))
  end
end

local function render(st)
  local buf = st.buf
  local lines, meta = {}, {}
  local on = 0
  for _, c in ipairs(st.changes) do
    if c.on then
      on = on + 1
    end
  end
  lines[1] = ("Değiştir: %s  →  %s"):format(st.q.pattern, st.q.replacement)
  lines[2] = ("Kapsam: %s · %s · .gitignore'a uyulur, gizli dosyalar hariç%s"):format(
    vim.fn.fnamemodify(st.root, ":~"),
    st.q.regex and "regex (ripgrep sözdizimi)" or "düz metin",
    st.q.glob and st.q.glob ~= "" and (" · glob: " .. st.q.glob) or ""
  )
  lines[3] = ("%d / %d değişiklik seçili   ·   a: uygula   x: satırı aç/kapat   X: dosyayı aç/kapat   Enter: dosyaya git   q: iptal"):format(on, #st.changes)
  lines[4] = ""
  local hls = { { 0, "NoctisAccent" }, { 1, "NoctisMuted" }, { 2, "NoctisDim" } }
  local last
  for i, c in ipairs(st.changes) do
    if c.rel ~= last then
      if last then
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = c.rel
      hls[#hls + 1] = { #lines - 1, "NoctisDiffFile" }
      meta[#lines] = { file = c.rel }
      last = c.rel
    end
    local mark = c.on and " " or "×"
    lines[#lines + 1] = ("%s %5d - %s"):format(mark, c.lnum, (c.old:gsub("\r$", "")))
    hls[#hls + 1] = { #lines - 1, c.on and "NoctisDiffDel" or "NoctisDim" }
    meta[#lines] = { idx = i }
    lines[#lines + 1] = ("%s %5s + %s"):format(mark, "", (c.new:gsub("\r$", "")))
    hls[#hls + 1] = { #lines - 1, c.on and "NoctisDiffAdd" or "NoctisDim" }
    meta[#lines] = { idx = i }
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(buf, ns, h[1], 0, { line_hl_group = h[2] })
  end
  st.meta = meta
end

---@param q {pattern:string, replacement:string, regex:boolean, glob?:string}
function M.preview(q)
  local r = require("noctis.project").root()
  local changes, err = M.collect(q, r)
  if not changes then
    U.error("Arama başarısız: " .. tostring(err))
    return
  end
  if #changes == 0 then
    U.info("Eşleşme bulunamadı.")
    return
  end
  if #changes > M.MAX then
    U.warn(("%d eşleşme var; güvenlik için en fazla %d değişiklik önizlenir. Aramayı daraltın (glob)."):format(#changes, M.MAX))
    return
  end
  vim.cmd("tabnew")
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "noctis-replace"
  pcall(api.nvim_buf_set_name, buf, "noctis://değiştir-önizleme")
  vim.wo.number = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false
  vim.wo.list = false
  local st = { buf = buf, q = q, changes = changes, root = r }
  render(st)
  local function cur_meta()
    return st.meta[api.nvim_win_get_cursor(0)[1]]
  end
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map("x", function()
    local m = cur_meta()
    if m and m.idx then
      st.changes[m.idx].on = not st.changes[m.idx].on
      local pos = api.nvim_win_get_cursor(0)
      render(st)
      pcall(api.nvim_win_set_cursor, 0, pos)
    end
  end, "Satırı hariç tut/dahil et")
  map("X", function()
    local m = cur_meta()
    local file = m and (m.file or (m.idx and st.changes[m.idx].rel))
    if file then
      local any_on = false
      for _, c in ipairs(st.changes) do
        if c.rel == file and c.on then
          any_on = true
        end
      end
      for _, c in ipairs(st.changes) do
        if c.rel == file then
          c.on = not any_on
        end
      end
      local pos = api.nvim_win_get_cursor(0)
      render(st)
      pcall(api.nvim_win_set_cursor, 0, pos)
    end
  end, "Dosyayı hariç tut/dahil et")
  map("<CR>", function()
    local m = cur_meta()
    if m and m.idx then
      local c = st.changes[m.idx]
      vim.cmd("tabprevious")
      vim.cmd("edit " .. vim.fn.fnameescape(c.path))
      pcall(api.nvim_win_set_cursor, 0, { c.lnum, 0 })
    end
  end, "Dosyaya git")
  map("a", function()
    local n, files = 0, {}
    for _, c in ipairs(st.changes) do
      if c.on then
        n = n + 1
        files[c.path] = true
      end
    end
    if n == 0 then
      U.info("Seçili değişiklik yok.")
      return
    end
    local msg = ("%d değişiklik %d dosyaya uygulanacak. Devam?"):format(n, vim.tbl_count(files))
    if vim.fn.confirm(msg, "&Uygula\n&Vazgeç", 2) == 1 then
      M.apply(st.changes)
      vim.cmd("tabclose")
    end
  end, "Uygula")
  map("q", function()
    vim.cmd("tabclose")
  end, "İptal")
end

function M.open()
  vim.ui.input({ prompt = "Ara: ", default = vim.fn.expand("<cword>") }, function(pattern)
    if not pattern or pattern == "" then
      return
    end
    vim.ui.input({ prompt = ("'%s' yerine: "):format(pattern) }, function(replacement)
      if replacement == nil then
        return
      end
      vim.ui.select({ "Düz metin", "Regex (ripgrep sözdizimi, $1 grupları)" }, { prompt = "Eşleştirme" }, function(_, idx)
        if not idx then
          return
        end
        vim.ui.input({ prompt = "Dosya filtresi (glob, boş = tüm proje): " }, function(glob)
          if glob == nil then
            return
          end
          M.preview({ pattern = pattern, replacement = replacement, regex = idx == 2, glob = vim.trim(glob) })
        end)
      end)
    end)
  end)
end

return M
