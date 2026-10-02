-- Command registry: the command palette, keymaps, which-key groups and the
-- documentation (docs/KEYMAPS.md) are all fed from this single list.
local M = {}

---@class noctis.Command
---@field id string            unique id, e.g. "files.find"
---@field title string         name shown in the palette
---@field desc? string         short description
---@field group string         category (File, Code, AI ...)
---@field keys? string         default Normal mode key
---@field mode? string|string[] key mode (default "n")
---@field run fun()            the action to run
---@field check? fun():boolean,string?  availability and reason
---@field palette? boolean     false hides it from the palette

---@type noctis.Command[]
M.list = {}
---@type table<string, noctis.Command>
M.by_id = {}

-- which-key groups (first key after leader)
M.groups = {
  { "<leader>a", "AI Workbench" },
  { "<leader>b", "Buffer" },
  { "<leader>c", "Code" },
  { "<leader>f", "File / Find" },
  { "<leader>g", "Git" },
  { "<leader>h", "Help / System" },
  { "<leader>p", "Project" },
  { "<leader>q", "Quit / Session" },
  { "<leader>s", "Search / Replace" },
  { "<leader>t", "Terminal / Tasks" },
  { "<leader>u", "Interface" },
  { "<leader>w", "Window" },
  { "<leader>x", "Diagnostics" },
}

---@param spec noctis.Command
function M.add(spec)
  assert(spec.id and spec.title and spec.run and spec.group, "missing command field: " .. vim.inspect(spec.id))
  assert(not M.by_id[spec.id], "duplicate command id: " .. spec.id)
  M.list[#M.list + 1] = spec
  M.by_id[spec.id] = spec
end

---@return boolean ok, string? reason
function M.available(cmd)
  if type(cmd) == "string" then
    cmd = M.by_id[cmd]
  end
  if not cmd then
    return false, "unknown command"
  end
  if cmd.check then
    local ok, ok2, reason = pcall(cmd.check)
    if not ok then
      return false, tostring(ok2)
    end
    return ok2 ~= false, reason
  end
  return true
end

---@param id string
function M.run(id)
  local cmd = M.by_id[id]
  if not cmd then
    require("noctis.util").error("Unknown command: " .. tostring(id))
    return
  end
  local ok, reason = M.available(cmd)
  if not ok then
    require("noctis.util").warn(("%s is unavailable: %s"):format(cmd.title, reason or "missing requirement"))
    return
  end
  local ok2, err = xpcall(cmd.run, debug.traceback)
  if not ok2 then
    require("noctis.util").log("ERROR", ("command %s: %s"):format(id, err))
    require("noctis.util").error(("%s failed: %s"):format(cmd.title, tostring(err):match("^[^\n]*")))
  end
end

--- Effective key with user overrides (false = disabled)
---@return string|false|nil
function M.effective_keys(cmd)
  local user = require("noctis.config").options.keymaps or {}
  if user[cmd.id] ~= nil then
    return user[cmd.id]
  end
  return cmd.keys
end

local function modes(cmd)
  local m = cmd.mode or "n"
  return type(m) == "table" and m or { m }
end

--- Find commands bound to the same mode+key combination, and prefix conflicts.
---@return string[] problems
function M.conflicts()
  local seen, problems = {}, {}
  local leader = vim.g.mapleader or " "
  local function norm(lhs)
    return vim.api.nvim_replace_termcodes(lhs:gsub("<leader>", leader), true, true, true)
  end
  local all = {}
  for _, cmd in ipairs(M.list) do
    local keys = M.effective_keys(cmd)
    if keys then
      for _, mode in ipairs(modes(cmd)) do
        local k = mode .. "\0" .. norm(keys)
        if seen[k] then
          problems[#problems + 1] = ("%s (%s): `%s` and `%s` use the same key"):format(keys, mode, seen[k], cmd.id)
        else
          seen[k] = cmd.id
        end
        all[#all + 1] = { mode = mode, lhs = norm(keys), id = cmd.id, keys = keys }
      end
    end
  end
  -- If one key is a prefix of another (e.g. <leader>f and <leader>ff),
  -- the shorter one causes a timeout wait.
  for _, a in ipairs(all) do
    for _, b in ipairs(all) do
      if a ~= b and a.mode == b.mode and #a.lhs < #b.lhs and b.lhs:sub(1, #a.lhs) == a.lhs then
        problems[#problems + 1] = ("%s (%s) `%s` is a prefix of `%s`; it causes a timeout delay"):format(
          a.keys,
          a.mode,
          a.id,
          b.id
        )
      end
    end
  end
  return problems
end

--- Apply every key in the registry.
function M.apply_keymaps()
  for _, cmd in ipairs(M.list) do
    local keys = M.effective_keys(cmd)
    if keys then
      vim.keymap.set(modes(cmd), keys, function()
        M.run(cmd.id)
      end, { desc = cmd.title, silent = true })
    end
  end
  -- Report unknown ids the user gave in overrides
  for id in pairs(require("noctis.config").options.keymaps or {}) do
    if not M.by_id[id] then
      require("noctis.util").warn(("keymaps: unknown command id `%s` (list them with `:NoctisKeys`)"):format(id))
    end
  end
end

--- Display names for special keys: <leader>ff -> Space f f
local special = {
  leader = "Space",
  space = "Space",
  localleader = "\\",
  cr = "Enter",
  enter = "Enter",
  esc = "Esc",
  tab = "Tab",
  bs = "Backspace",
  up = "↑",
  down = "↓",
  left = "←",
  right = "→",
}

--- Format a key for display: <leader>ff -> "Space f f",
--- <leader><space> -> "Space Space", <C-s> -> "Ctrl+s"
function M.pretty_keys(keys)
  if not keys then
    return ""
  end
  local tokens = {}
  local i = 1
  while i <= #keys do
    local tok = keys:match("^<[^<>]+>", i)
    if tok then
      i = i + #tok
      local inner = tok:sub(2, -2)
      local mod, key = inner:match("^([CcSsMmAa])%-(.+)$")
      if mod then
        local name = ({ c = "Ctrl", s = "Shift", m = "Alt", a = "Alt" })[mod:lower()]
        tokens[#tokens + 1] = name .. "+" .. (special[key:lower()] or key)
      else
        tokens[#tokens + 1] = special[inner:lower()] or inner
      end
    else
      tokens[#tokens + 1] = keys:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(tokens, " ")
end

--- Generate the contents of docs/KEYMAPS.md
function M.markdown()
  local out = {
    "# NOCTIS keymaps and commands",
    "",
    "> This file is generated from the command registry in `app/lua/noctis/commands.lua`",
    "> (`tests/gen-keymaps.sh`). Don't edit it by hand; the test suite checks that it's up to date.",
    "",
    "Every command can be found by name in the `Space Space` command palette. The table is for Normal mode.",
    "",
  }
  local by_group, order = {}, {}
  for _, cmd in ipairs(M.list) do
    if cmd.palette ~= false then
      if not by_group[cmd.group] then
        by_group[cmd.group] = {}
        order[#order + 1] = cmd.group
      end
      table.insert(by_group[cmd.group], cmd)
    end
  end
  for _, g in ipairs(order) do
    out[#out + 1] = "## " .. g
    out[#out + 1] = ""
    out[#out + 1] = "| Key | Command | Description |"
    out[#out + 1] = "| --- | --- | --- |"
    for _, cmd in ipairs(by_group[g]) do
      local k = cmd.keys and ("`" .. M.pretty_keys(cmd.keys) .. "`") or "—"
      out[#out + 1] = ("| %s | %s | %s |"):format(k, cmd.title, (cmd.desc or ""):gsub("|", "\\|"))
    end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

return M
