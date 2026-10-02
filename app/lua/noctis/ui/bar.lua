-- Fits winbar/statusline parts to the window width.
-- Parts are dropped by priority (highest `drop` first); remaining long text
-- is shortened from the end. This way important information (tabs, labels)
-- is never cut off from the left.
local M = {}

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

---@class noctis.BarPart
---@field text string     visible text (raw, unescaped)
---@field hl? string      highlight group
---@field drop? integer   0 = never drop; higher values are dropped first
---@field click? string   %N@fn@ prefix (optional)
---@field right? boolean  right-aligned section

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
  -- Drop the part with the highest drop value until everything fits
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
  -- If it still doesn't fit, shorten the longest non-droppable part
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
