-- Satır parçaları (satır sonu karakterleriyle birlikte) üzerinde diff ve
-- hunk işlemleri. Satırlar terminatörleriyle tutulduğu için CRLF ve son
-- satırdaki newline farkı dahil geri alma bayt düzeyinde kesindir.
local M = {}

M.MAX_DIFF_BYTES = 8 * 1024 * 1024

--- "a\nb" -> {"a\n", "b"}
function M.chunks(text)
  local out, pos, n = {}, 1, #text
  while pos <= n do
    local nl = text:find("\n", pos, true)
    if not nl then
      out[#out + 1] = text:sub(pos)
      break
    end
    out[#out + 1] = text:sub(pos, nl)
    pos = nl + 1
  end
  return out
end

--- Görüntüleme için satır (terminatörsüz)
function M.display(chunk)
  return (chunk:gsub("\r?\n$", ""))
end

---@return integer[][]? hunks {a_start, a_count, b_start, b_count}
function M.diff(a, b)
  if #a > M.MAX_DIFF_BYTES or #b > M.MAX_DIFF_BYTES then
    return nil
  end
  local ok, res = pcall(vim.text.diff, a, b, { result_type = "indices", algorithm = "histogram" })
  if not ok then
    return nil
  end
  return res
end

function M.stats(hunks)
  local adds, dels = 0, 0
  for _, h in ipairs(hunks or {}) do
    dels = dels + h[2]
    adds = adds + h[4]
  end
  return adds, dels
end

--- Mevcut metinde yalnız seçilen hunk'ı başlangıç sürümüne döndür.
---@param base string
---@param cur string
---@param h integer[]
---@return string
function M.revert_hunk(base, cur, h)
  local bc_, cc_ = M.chunks(base), M.chunks(cur)
  local as, ac, bs, bc = h[1], h[2], h[3], h[4]
  local out = {}
  local at = bc > 0 and bs or bs + 1
  for i = 1, at - 1 do
    out[#out + 1] = cc_[i]
  end
  for i = as, as + ac - 1 do
    out[#out + 1] = bc_[i]
  end
  for i = at + bc, #cc_ do
    out[#out + 1] = cc_[i]
  end
  return table.concat(out)
end

--- İmleç satırına (mevcut dosyada) karşılık gelen hunk indeksi
function M.hunk_at(hunks, line)
  local best, bestd
  for i, h in ipairs(hunks or {}) do
    local s = h[3]
    local e = h[4] > 0 and (h[3] + h[4] - 1) or h[3]
    if h[4] == 0 then
      s, e = math.max(1, h[3]), h[3] + 1
    end
    if line >= s and line <= e then
      return i
    end
    local d = math.min(math.abs(line - s), math.abs(line - e))
    if not bestd or d < bestd then
      best, bestd = i, d
    end
  end
  return best, bestd
end

--- Birleşik diff satırları
---@return string[] lines, {row:integer, kind:string, hunk?:integer, line?:integer}[] meta
function M.unified(base, cur, hunks, ctx)
  ctx = ctx or 3
  local a, b = M.chunks(base), M.chunks(cur)
  local lines, meta = {}, {}
  local function add(text, kind, hi, line)
    lines[#lines + 1] = text
    meta[#lines] = { kind = kind, hunk = hi, line = line }
  end
  for hi, h in ipairs(hunks) do
    local as, ac, bs, bc = h[1], h[2], h[3], h[4]
    local b_first = bc > 0 and bs or bs + 1
    local pre_from = math.max(1, b_first - ctx)
    add(("@@ -%d,%d +%d,%d @@  hunk %d/%d"):format(as, ac, bs, bc, hi, #hunks), "hunk", hi, b_first)
    for i = pre_from, b_first - 1 do
      add("  " .. M.display(b[i] or ""), "ctx", hi, i)
    end
    for i = as, as + ac - 1 do
      add("- " .. M.display(a[i] or ""), "del", hi, b_first)
    end
    for i = bs, bs + bc - 1 do
      add("+ " .. M.display(b[i] or ""), "add", hi, i)
    end
    local after = b_first + bc
    for i = after, math.min(#b, after + ctx - 1) do
      add("  " .. M.display(b[i] or ""), "ctx", hi, i)
    end
    add("", "sep", hi)
  end
  return lines, meta
end

return M
