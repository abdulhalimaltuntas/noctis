-- Komut paleti: registry'deki tüm komutlar ad, açıklama, grup veya kısayolla
-- aranır. Kullanılamayan komutlar gerekçesiyle gösterilir, çalışıyormuş gibi
-- sunulmaz.
local M = {}

local R = require("noctis.registry")

local function build_items()
  local items = {}
  for _, c in ipairs(R.list) do
    if c.palette ~= false then
      local ok, reason = R.available(c)
      local keys = R.pretty_keys(R.effective_keys(c) or nil)
      items[#items + 1] = {
        id = c.id,
        title = c.title,
        desc = c.desc or "",
        group = c.group,
        keys = keys,
        ok = ok,
        reason = reason,
        text = table.concat({ c.title, c.desc or "", c.group, keys, c.id }, " "),
      }
    end
  end
  -- Kullanılabilenler önce; sonra kayıt sırası
  table.sort(items, function(a, b)
    if a.ok ~= b.ok then
      return a.ok
    end
    return false
  end)
  return items
end

local KEYW = 12

local function format(item)
  local ret = {}
  local k = item.keys ~= "" and item.keys or ""
  ret[#ret + 1] = { k .. string.rep(" ", math.max(1, KEYW - vim.fn.strdisplaywidth(k))), "NoctisPaletteKey" }
  if item.ok then
    ret[#ret + 1] = { item.title, "Normal" }
    ret[#ret + 1] = { "  " .. item.group, "NoctisPaletteGroup" }
    if item.desc ~= "" then
      ret[#ret + 1] = { "  " .. item.desc, "NoctisPaletteDesc" }
    end
  else
    ret[#ret + 1] = { item.title, "NoctisPaletteUnavailable" }
    ret[#ret + 1] = { "  kullanılamaz: " .. (item.reason or "gereksinim eksik"), "NoctisWarning" }
  end
  return ret
end

function M.open()
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisPaletteOpened", modeline = false })
  local items = build_items()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker then
    local cols = vim.o.columns
    Snacks.picker.pick({
      source = "noctis_commands",
      title = "Komut paleti",
      items = items,
      format = format,
      preview = "none",
      matcher = { fuzzy = true, sort_empty = false },
      layout = {
        preview = false,
        layout = {
          backdrop = false,
          row = 2,
          width = math.min(100, cols - 4),
          min_width = math.min(60, cols - 4),
          height = 0.55,
          border = require("noctis.ui.icons").border_name():find(",") and "single" or "rounded",
          box = "vertical",
          title = "{title}",
          title_pos = "center",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
      },
      confirm = function(picker, item)
        picker:close()
        if item then
          vim.schedule(function()
            R.run(item.id)
          end)
        end
      end,
    })
    return
  end
  -- Eklentisiz yedek: yerleşik seçim listesi
  vim.ui.select(items, {
    prompt = "Komut paleti",
    format_item = function(it)
      local k = it.keys ~= "" and ("[" .. it.keys .. "] ") or ""
      return k .. it.title .. (it.ok and "" or ("  (kullanılamaz: " .. (it.reason or "?") .. ")"))
    end,
  }, function(it)
    if it then
      R.run(it.id)
    end
  end)
end

return M
