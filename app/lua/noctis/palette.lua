-- Command palette: every registry command is searchable by name, description,
-- group or key. Commands that can't run are shown with the reason, never
-- presented as if they worked. Recently used commands come first.
local M = {}

local R = require("noctis.registry")

-- Recently used commands (frecency): the most used of the last weeks come
-- first when the palette opens, and win ties while searching. Only commands run
-- from the palette count; the keys you already know don't crowd the list.
local RECENT = 6 -- shown at the top with an empty query
local HALF_LIFE = 14 * 86400 -- a use counts half as much after two weeks
local KEEP = 100

local function usage_path()
  return require("noctis.util").state_dir() .. "/palette.json"
end

local function read_usage()
  local st = require("noctis.util").json_read(usage_path())
  return type(st) == "table" and type(st.uses) == "table" and st.uses or {}
end

local function frecency(u, now)
  if type(u) ~= "table" or type(u.n) ~= "number" or type(u.t) ~= "number" then
    return 0
  end
  return u.n * 0.5 ^ (math.max(0, now - u.t) / HALF_LIFE)
end

--- Record that a command was run from the palette.
---@param id string
function M.record(id)
  local uses, now = read_usage(), os.time()
  local u = uses[id] or { n = 0, t = now }
  -- Decay the old count to now, then add this use
  uses[id] = { n = frecency(u, now) + 1, t = now }
  local ids = vim.tbl_keys(uses)
  if #ids > KEEP then
    table.sort(ids, function(a, b)
      return frecency(uses[a], now) > frecency(uses[b], now)
    end)
    for i = KEEP + 1, #ids do
      uses[ids[i]] = nil
    end
  end
  require("noctis.util").json_write(usage_path(), { version = 1, uses = uses })
end

local function build_items()
  local uses, now = read_usage(), os.time()
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
        score_use = ok and frecency(uses[c.id], now) or 0,
        -- Searchable: name, key, description (the group name would pollute search; it's only displayed)
        text = table.concat({ c.title, keys, c.desc or "" }, "  "),
      }
    end
  end
  -- The top RECENT used commands are marked; table.sort isn't stable, so keep an index
  local ranked = {}
  for i, it in ipairs(items) do
    it.order = i
    if it.score_use > 0 then
      ranked[#ranked + 1] = it
    end
  end
  table.sort(ranked, function(a, b)
    return a.score_use > b.score_use
  end)
  for i = 1, math.min(RECENT, #ranked) do
    ranked[i].recent = i
  end
  -- Available commands first; among them the recent ones, then registration order
  table.sort(items, function(a, b)
    if a.ok ~= b.ok then
      return a.ok
    end
    if (a.recent ~= nil) ~= (b.recent ~= nil) then
      return a.recent ~= nil
    end
    if a.recent then
      return a.recent < b.recent
    end
    return a.order < b.order
  end)
  return items
end

local KEYW = 12

local function format(item)
  local ret = {}
  local icon, icon_hl = require("noctis.ui.icons").group(item.group)
  if icon ~= "" then
    ret[#ret + 1] = { icon .. " ", item.ok and icon_hl or "NoctisPaletteUnavailable" }
  end
  local k = item.keys ~= "" and item.keys or ""
  ret[#ret + 1] = { k .. string.rep(" ", math.max(1, KEYW - vim.fn.strdisplaywidth(k))), "NoctisPaletteKey" }
  if item.ok then
    ret[#ret + 1] = { item.title, "Normal" }
    ret[#ret + 1] = { "  " .. item.group, "NoctisPaletteGroup" }
    if item.desc ~= "" then
      ret[#ret + 1] = { "  " .. item.desc, "NoctisPaletteDesc" }
    end
    if item.recent then
      ret[#ret + 1] = { "  · recent", "NoctisPaletteRecent" }
    end
  else
    ret[#ret + 1] = { item.title, "NoctisPaletteUnavailable" }
    ret[#ret + 1] = { "  unavailable: " .. (item.reason or "missing requirement"), "NoctisWarning" }
  end
  return ret
end

local function run(item)
  if item.ok then
    pcall(M.record, item.id)
  end
  R.run(item.id)
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
            run(item)
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
      local tail = it.ok and (it.recent and "  (recent)" or "") or ("  (unavailable: " .. (it.reason or "?") .. ")")
      return k .. it.title .. tail
    end,
  }, function(it)
    if it then
      run(it)
    end
  end)
end

return M
