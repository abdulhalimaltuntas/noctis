-- Winbar/statusline parçalarını pencere genişliğine sığdırır.
-- Parçalar öncelik sırasına göre (yüksek `drop` önce) atılır; kalan uzun
-- metin sondan kısaltılır. Böylece önemli bilgi (sekmeler, etiket) soldan
-- kırpılmaz.
local M = {}

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

---@class noctis.BarPart
---@field text string     görünen metin (ham, kaçışsız)
---@field hl? string      highlight grubu
---@field drop? integer   0 = asla atma; büyük değer önce atılır
---@field click? string   %N@fn@ öneki (isteğe bağlı)
---@field right? boolean  sağa yaslı bölüm

---@param parts noctis.BarPart[]
---@param width integer
function M.build(parts, width)
  local keep = {}
  for i, p in ipairs(parts) do
    keep[i] = true
  end
  local function total()
    local w = 0
    for i, p in ipairs(parts) do
      if keep[i] then
        w = w + vim.fn.strdisplaywidth(p.text)
      end
    end
    return w
  end
  -- Sığana kadar en yüksek drop değerli parçayı at
  while total() > width do
    local best, bi = 0, nil
    for i, p in ipairs(parts) do
      if keep[i] and (p.drop or 0) > best then
        best, bi = p.drop, i
      end
    end
    if not bi then
      break
    end
    keep[bi] = false
  end
  -- Hâlâ sığmıyorsa en uzun atılamaz parçayı kısalt
  local over = total() - width
  if over > 0 then
    local li, lw = nil, 0
    for i, p in ipairs(parts) do
      local w = vim.fn.strdisplaywidth(p.text)
      if keep[i] and w > lw then
        li, lw = i, w
      end
    end
    if li then
      parts[li].text = require("noctis.util").truncate(parts[li].text, math.max(1, lw - over))
    end
  end
  local left, right = {}, {}
  for i, p in ipairs(parts) do
    if keep[i] then
      local s = (p.click or "") .. "%#" .. (p.hl or "Normal") .. "#" .. esc(p.text) .. (p.click and "%X" or "")
      if p.right then
        right[#right + 1] = s
      else
        left[#left + 1] = s
      end
    end
  end
  return table.concat(left) .. "%=" .. table.concat(right)
end

return M
