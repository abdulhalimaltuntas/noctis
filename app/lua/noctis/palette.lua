-- Command palette: every registry command is searchable by name, description,
-- group or key. Commands that can't run are shown with the reason, never
-- presented as if they worked.
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
        -- Searchable: name, key, description (the group name would pollute search; it's only displayed)
        text = table.concat({ c.title, keys, c.desc or "" }, "  "),
      }
    end
  end
  -- Available commands first, then registration order (table.sort isn't stable: use an index)
  for i, it in ipairs(items) do
    it.order = i
  end
  table.sort(items, function(a, b)
    if a.ok ~= b.ok then
      return a.ok
    end
    return a.order < b.order
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
    ret[#ret + 1] = { "  unavailable: " .. (item.reason or "missing requirement"), "NoctisWarning" }
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
      title = "Command palette",
      items = items,
      format = format,
      preview = "none",
      matcher = { fuzzy = true, sort_empty = false, filename_bonus = false, frecency = false, cwd_bonus = false },
      -- On equal score, registration order (meaningful grouping) is kept
      sort = { fields = { "score:desc", "idx" } },
      layout = {
        preview = false,
        layout = {
          backdrop = false,
          row = 2,
          width = math.min(100, cols - 4),
          min_width = math.min(60, cols - 4),
          height = 0.55,
          border = require("noctis.ui.icons").border_opt(),
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
  -- Fallback without plugins: the built-in selection list
  vim.ui.select(items, {
    prompt = "Command palette",
    format_item = function(it)
      local k = it.keys ~= "" and ("[" .. it.keys .. "] ") or ""
      return k .. it.title .. (it.ok and "" or ("  (unavailable: " .. (it.reason or "?") .. ")"))
    end,
  }, function(it)
    if it then
      R.run(it.id)
    end
  end)
end

return M
