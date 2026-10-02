-- Üst çubuk: açık dosyalar (buffer listesi). Neovim sekmeleri (tabpage) farklı
-- bir kavramdır; yalnız birden fazla sekme varken sağda "sekme 2/3" olarak
-- gösterilir. Aynı dosya iki ayrı çubukta tekrarlanmaz.
local M = {}

local api = vim.api
local icons = require("noctis.ui.icons")

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

local function file_bufs()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and api.nvim_buf_is_valid(b) and vim.bo[b].buftype ~= "terminal" then
      out[#out + 1] = b
    end
  end
  return out
end

--- Aynı ada sahip dosyalar için üst klasörü ekleyerek ayırt edici etiket üret
local function labels(bufs)
  local tails, out = {}, {}
  for _, b in ipairs(bufs) do
    local name = api.nvim_buf_get_name(b)
    local tail = name == "" and icons.get().file.unnamed or vim.fn.fnamemodify(name, ":t")
    tails[tail] = (tails[tail] or 0) + 1
    out[b] = tail
  end
  for _, b in ipairs(bufs) do
    local name = api.nvim_buf_get_name(b)
    if name ~= "" and tails[out[b]] > 1 then
      out[b] = vim.fn.fnamemodify(name, ":h:t") .. "/" .. out[b]
    end
  end
  return out
end

function _G.NoctisTablineClick(bufnr, clicks, button)
  if button == "m" then
    require("noctis.buffers").delete(bufnr)
  elseif api.nvim_buf_is_valid(bufnr) then
    -- Bir yan panel odaktaysa editör penceresine geç
    require("noctis.ui.layout").focus_editor()
    api.nvim_set_current_buf(bufnr)
  end
end

function M.render()
  local bufs = file_bufs()
  local cur = api.nvim_get_current_buf()
  local cols = vim.o.columns
  local names = labels(bufs)
  local mod = icons.get().file.modified

  local right = ""
  local tabs = #api.nvim_list_tabpages()
  if tabs > 1 then
    right = ("%%#NoctisTabPage# sekme %d/%d "):format(vim.fn.tabpagenr(), tabs)
  end
  local right_w = tabs > 1 and #(" sekme 0/0 ") + 2 or 0

  local items = {}
  local active_idx = 1
  for i, b in ipairs(bufs) do
    local is_cur = b == cur
    if is_cur then
      active_idx = i
    end
    local label = require("noctis.util").truncate(names[b], 28)
    local modified = vim.bo[b].modified
    local text = " " .. label .. (modified and (" " .. mod) or "  ") .. " "
    local group = is_cur and "NoctisTabActive" or "NoctisTabInactive"
    local s = ("%%%d@v:lua.NoctisTablineClick@"):format(b)
    if is_cur then
      s = s .. "%#NoctisTabActiveMark#" .. (icons.enabled() and "▎" or ">")
    else
      s = s .. "%#" .. group .. "# "
    end
    s = s .. "%#" .. group .. "#" .. esc(" " .. label)
    if modified then
      s = s .. "%#" .. (is_cur and "NoctisTabModifiedActive" or "NoctisTabModified") .. "# " .. mod .. " "
    else
      s = s .. "%#" .. group .. "#   "
    end
    s = s .. "%X"
    items[i] = { s = s, w = vim.fn.strdisplaywidth(text) + 1 }
  end

  if #items == 0 then
    return "%#NoctisTabFill#%=" .. right
  end

  -- Taşma: aktif buffer'ı görünür tutan pencere
  local avail = cols - right_w - 4
  local first, last = active_idx, active_idx
  local used = items[active_idx].w
  while true do
    local grew = false
    if last < #items and used + items[last + 1].w <= avail then
      last = last + 1
      used = used + items[last].w
      grew = true
    end
    if first > 1 and used + items[first - 1].w <= avail then
      first = first - 1
      used = used + items[first].w
      grew = true
    end
    if not grew then
      break
    end
  end

  local out = {}
  if first > 1 then
    out[#out + 1] = ("%%#NoctisTabRight# ‹%d"):format(first - 1)
  end
  for i = first, last do
    out[#out + 1] = items[i].s
  end
  if last < #items then
    out[#out + 1] = ("%%#NoctisTabRight#%d› "):format(#items - last)
  end
  return table.concat(out) .. "%#NoctisTabFill#%=" .. right
end

function M.setup()
  vim.o.tabline = "%!v:lua.require'noctis.ui.tabline'.render()"
end

return M
