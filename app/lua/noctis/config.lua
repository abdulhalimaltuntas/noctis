-- User configuration: defaults + schema validation.
-- User file: stdpath("config")/config.lua  (returns a Lua table)
-- Updates never touch this file.
local M = {}

M.defaults = {
  theme = "midnight-violet", -- "midnight-violet" | "glacier" | "amber"
  transparent = false, -- let the terminal provide the editor background
  icons = true, -- Nerd Font icons; false uses plain characters
  borders = "rounded", -- "rounded" | "single" | "ascii"
  truecolor = "auto", -- "auto" | true | false
  welcome = true, -- short tour on first launch
  ui = {
    relative_numbers = false,
    indent_guides = true,
    cursorline = true,
    explorer_width = 30,
    wrap = false,
    typing_animation = true, -- brief glow behind typed characters (needs truecolor)
  },
  diagnostics = {
    virtual_text = true,
    signs = true,
    underline = true,
  },
  format_on_save = {
    enabled = false,
    filetypes = {}, -- only these filetypes; if empty and enabled=true, all of them
    timeout_ms = 1500,
  },
  languages = { "python", "javascript", "html", "json", "lua", "bash" },
  bigfile = {
    size = 2 * 1024 * 1024, -- bytes
    lines = 50000,
  },
  clipboard = "auto", -- "auto" | "system" | "internal"
  session = {
    autosave = true, -- save the project layout on quit; restoring is always an explicit command
  },
  keymaps = {}, -- { ["command.id"] = "<leader>xy" | false }
  tasks = {}, -- { { name = "Test", cmd = { "pytest" }, cwd = nil } }
  ai = {
    profiles = {}, -- extend/override the default profiles: { aider = { label = "Aider", cmd = { "aider" } } }
    layout = "auto", -- "auto" | "right" | "bottom" | "full"
    width = 0.42, -- right panel ratio
    height = 0.40, -- bottom panel ratio
    baseline = {
      max_files = 5000,
      max_file_size = 1024 * 1024,
      max_total_size = 64 * 1024 * 1024,
      exclude = {}, -- extra exclude patterns (simple gitignore-style globs)
      respect_gitignore = true,
    },
    watch = {
      debounce_ms = 250,
      reconcile_ms = 4000,
      max_dirs = 4000,
    },
    retention_days = 14,
    max_store_mb = 512,
  },
}

-- Schema: the defaults define the types; extra constraints live here.
local enums = {
  theme = { "midnight-violet", "glacier", "amber" },
  borders = { "rounded", "single", "ascii" },
  clipboard = { "auto", "system", "internal" },
  ["ai.layout"] = { "auto", "right", "bottom", "full" },
}
local special = {
  truecolor = function(v)
    return v == "auto" or type(v) == "boolean", 'must be "auto", true or false'
  end,
  ["ui.explorer_width"] = function(v)
    return type(v) == "number" and v >= 16 and v <= 80, "must be a number between 16 and 80"
  end,
  ["ai.width"] = function(v)
    return type(v) == "number" and v > 0.15 and v < 0.85, "must be a ratio between 0.15 and 0.85"
  end,
  ["ai.height"] = function(v)
    return type(v) == "number" and v > 0.15 and v < 0.85, "must be a ratio between 0.15 and 0.85"
  end,
}
-- Fields with free-form content (keys chosen by the user)
local open = {
  keymaps = true,
  tasks = true,
  languages = true,
  ["ai.profiles"] = true,
  ["format_on_save.filetypes"] = true,
  ["ai.baseline.exclude"] = true,
}

---@type string[]
M.errors = {}
---@type string[]
M.warnings = {}

local function is_list(t)
  return type(t) == "table" and (vim.tbl_isempty(t) or vim.islist(t))
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then
      return true
    end
  end
  return false
end

--- Validate the user table against the defaults and merge.
--- Invalid values are reported and replaced by the default.
---@return table merged
function M.validate(user, defaults, prefix, errors, warnings)
  local out = vim.deepcopy(defaults)
  if type(user) ~= "table" then
    return out
  end
  for k, v in pairs(user) do
    local key = prefix and (prefix .. "." .. k) or tostring(k)
    local def = defaults[k]
    if def == nil and not special[key] then
      warnings[#warnings + 1] = ("unknown setting `%s` ignored (possibly a typo)"):format(key)
    elseif special[key] then
      local ok, why = special[key](v)
      if ok then
        out[k] = v
      else
        errors[#errors + 1] = ("`%s` is invalid: %s (given: %s)"):format(key, why, vim.inspect(v))
      end
    elseif open[key] then
      if type(v) ~= "table" then
        errors[#errors + 1] = ("`%s` must be a table (given: %s)"):format(key, type(v))
      else
        out[k] = v
      end
    elseif type(def) == "table" and not is_list(def) then
      if type(v) ~= "table" then
        errors[#errors + 1] = ("`%s` must be a table (given: %s)"):format(key, type(v))
      else
        out[k] = M.validate(v, def, key, errors, warnings)
      end
    elseif type(v) ~= type(def) then
      errors[#errors + 1] = ("`%s` expected %s, got %s"):format(key, type(def), type(v))
    elseif enums[key] and not contains(enums[key], v) then
      errors[#errors + 1] = ("`%s` must be one of: %s (given: %s)"):format(
        key,
        table.concat(enums[key], ", "),
        tostring(v)
      )
    else
      out[k] = v
    end
  end
  return out
end

M.path = vim.fn.stdpath("config") .. "/config.lua"

---@type table
M.options = vim.deepcopy(M.defaults)

--- Load the user file. On a syntax error, the defaults are used and the
--- error is made visible (never swallowed silently).
function M.load()
  M.errors, M.warnings = {}, {}
  local user = {}
  if vim.uv.fs_stat(M.path) then
    local chunk, lerr = loadfile(M.path)
    if not chunk then
      M.errors[#M.errors + 1] = "config.lua could not be read: " .. tostring(lerr)
    else
      local ok, res = pcall(chunk)
      if not ok then
        M.errors[#M.errors + 1] = "error while running config.lua: " .. tostring(res)
      elseif type(res) ~= "table" then
        M.errors[#M.errors + 1] = "config.lua must return a table (example: return { theme = \"glacier\" })"
      else
        user = res
      end
    end
  end
  M.options = M.validate(user, M.defaults, nil, M.errors, M.warnings)
  -- The persisted theme choice (Space u t) applies when the user file sets no theme.
  if user.theme == nil then
    local st = require("noctis.util").json_read(vim.fn.stdpath("state") .. "/noctis/ui.json")
    if st and contains(enums.theme, st.theme) then
      M.options.theme = st.theme
    end
  end
  return M.options
end

function M.report()
  local U = require("noctis.util")
  for _, e in ipairs(M.errors) do
    U.log("ERROR", "config: " .. e)
  end
  for _, w in ipairs(M.warnings) do
    U.log("WARN", "config: " .. w)
  end
  if #M.errors > 0 then
    U.error(
      "Configuration errors (defaults were used):\n• " .. table.concat(M.errors, "\n• ") .. "\nFile: " .. M.path
    )
  end
  if #M.warnings > 0 then
    U.warn("Configuration warnings:\n• " .. table.concat(M.warnings, "\n• "))
  end
end

setmetatable(M, {
  __index = function(_, k)
    return M.options[k]
  end,
})

return M
