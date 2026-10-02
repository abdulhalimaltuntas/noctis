-- Review scope: which files' content goes into the baseline.
-- Default: .gitignore is respected; dependency, build, cache and sensitive
-- files are not recorded. Symbolic links are not followed.
local M = {}

local U = require("noctis.util")

-- Folders never watched (the watcher doesn't enter them either)
M.skip_dirs = {
  [".git"] = true,
  [".hg"] = true,
  [".svn"] = true,
  ["node_modules"] = true,
  [".venv"] = true,
  ["venv"] = true,
  ["__pycache__"] = true,
  [".mypy_cache"] = true,
  [".pytest_cache"] = true,
  [".ruff_cache"] = true,
  [".tox"] = true,
  [".cache"] = true,
  [".next"] = true,
  [".nuxt"] = true,
  [".gradle"] = true,
  [".idea"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["target"] = true,
  ["coverage"] = true,
  [".terraform"] = true,
}

-- Sensitive files: content is never copied (a change is only reported)
M.sensitive = {
  "^%.env$",
  "^%.env%..+",
  "%.pem$",
  "%.key$",
  "%.p12$",
  "%.pfx$",
  "%.kdbx$",
  "^id_rsa",
  "^id_ed25519",
  "^id_ecdsa",
  "^%.npmrc$",
  "^%.pypirc$",
  "^%.netrc$",
  "^%.git%-credentials$",
  "^credentials$",
  "^credentials%.[%w]+$",
  "^secrets?%.[%w]+$",
  "^%.secrets?$",
}

function M.is_sensitive(rel)
  local name = vim.fn.fnamemodify(rel, ":t"):lower()
  for _, pat in ipairs(M.sensitive) do
    if name:find(pat) then
      return true
    end
  end
  return false
end

local function glob_to_lua(g)
  local p = g:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*%*", "\1"):gsub("%*", "[^/]*"):gsub("\1", ".*"):gsub("%?", ".")
  return "^" .. p .. "$"
end

--- User exclusions (config: ai.baseline.exclude)
function M.user_excluded(rel)
  for _, g in ipairs(require("noctis.config").options.ai.baseline.exclude or {}) do
    local pat = glob_to_lua(g)
    if rel:match(pat) or vim.fn.fnamemodify(rel, ":t"):match(pat) then
      return true
    end
  end
  return false
end

--- Is any component of the path a skipped folder?
function M.in_skipped_dir(rel)
  for part in rel:gmatch("[^/]+") do
    if M.skip_dirs[part] then
      return true
    end
  end
  return false
end

--- List project files (relative paths). .gitignore is applied.
---@return string[] files, string method
function M.list_files(root)
  local cfg = require("noctis.config").options.ai.baseline
  local files = {}
  if U.has("rg") then
    local args = { "rg", "--files", "--hidden", "--no-require-git", "--no-follow", "--color", "never" }
    if not cfg.respect_gitignore then
      args[#args + 1] = "--no-ignore"
    end
    for d in pairs(M.skip_dirs) do
      args[#args + 1] = "--glob"
      args[#args + 1] = "!**/" .. d .. "/**"
    end
    local res = vim.system(args, { cwd = root, text = true }):wait(60000)
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      files[#files + 1] = line:gsub("^%./", "")
    end
    table.sort(files)
    return files, cfg.respect_gitignore and "ripgrep (.gitignore applied)" or "ripgrep (ignore rules off)"
  end
  -- Fallback: a directory walk (gitignore can't be applied)
  for name, t in vim.fs.dir(root, {
    depth = 40,
    skip = function(dir)
      return not M.skip_dirs[vim.fn.fnamemodify(dir, ":t")]
    end,
  }) do
    if t == "file" then
      files[#files + 1] = name
    end
  end
  table.sort(files)
  return files, "directory scan (no ripgrep: .gitignore not applied)"
end

--- Which of the given new paths are not ignored? (.gitignore, .ignore)
--- Checked with ripgrep walking from the root.
---@param root string
---@param rels string[]
---@return table<string, boolean> the ones in scope
function M.not_ignored(root, rels)
  local cfg = require("noctis.config").options.ai.baseline
  local out = {}
  if not cfg.respect_gitignore or not U.has("rg") then
    for _, r in ipairs(rels) do
      out[r] = true
    end
    return out
  end
  -- ripgrep doesn't apply ignore rules to explicitly given paths, so it
  -- walks from the root and the candidate files are filtered with a glob whitelist.
  local args = { "rg", "--files", "--hidden", "--no-require-git", "--no-follow", "--color", "never" }
  for _, r in ipairs(rels) do
    args[#args + 1] = "--glob"
    args[#args + 1] = "/" .. r:gsub("[%[%]{}%*%?!\\]", "\\%0")
  end
  local res = vim.system(args, { cwd = root, text = true }):wait(15000)
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    out[(line:gsub("^%./", ""))] = true
  end
  return out
end

function M.is_binary(data)
  return data:sub(1, 8000):find("\0", 1, true) ~= nil
end

return M
