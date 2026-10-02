-- Git: branch info, changed files, file diff. Lazygit is optional; without it
-- the basic Git summary and diff features work. Operations such as commit/push
-- are only started explicitly by the user (NOCTIS never does them itself).
-- In a folder that isn't a Git repository, every feature is quietly disabled.
local M = {}

local U = require("noctis.util")
local api = vim.api

local cache = {} ---@type table<string, {branch?:string, at:integer}>

local function root()
  return require("noctis.project").root()
end

---@param r? string
---@return string? top
function M.toplevel(r)
  r = r or root()
  local res = vim.system({ "git", "-C", r, "rev-parse", "--show-toplevel" }, { text = true }):wait(3000)
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or "")
end

--- Cached branch name for the statusline (refreshed asynchronously)
function M.cached_branch()
  local r = root()
  local c = cache[r]
  local now = vim.uv.now()
  if not c or now - c.at > 5000 then
    cache[r] = cache[r] or { at = now }
    cache[r].at = now
    if U.has("git") then
      vim.system({ "git", "-C", r, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(res)
        cache[r].branch = res.code == 0 and vim.trim(res.stdout or "") or nil
        vim.schedule(function()
          vim.cmd("redrawstatus")
        end)
      end)
    end
  end
  return cache[r] and cache[r].branch
end

---@return {path:string, x:string, y:string}[]?, string? branch_line
function M.status_entries(r)
  local res = vim.system({ "git", "-C", r, "status", "--porcelain=v1", "-b", "-z", "--untracked-files=all" }, { text = true }):wait(10000)
  if res.code ~= 0 then
    return nil
  end
  local items, branch = {}, nil
  local parts = vim.split(res.stdout or "", "\0", { plain = true })
  local i = 1
  while i <= #parts do
    local p = parts[i]
    if p:sub(1, 2) == "##" then
      branch = p:sub(4)
    elseif #p > 3 then
      local x, y, path = p:sub(1, 1), p:sub(2, 2), p:sub(4)
      items[#items + 1] = { x = x, y = y, path = path }
      if x == "R" or x == "C" then
        i = i + 1 -- on a rename the old name comes as a separate field
      end
    end
    i = i + 1
  end
  return items, branch
end

--- Local Git summary (when lazygit isn't available)
function M.summary()
  local r = M.toplevel()
  if not r then
    U.info("This folder isn't a Git repository.")
    return
  end
  local items, branch = M.status_entries(r)
  if not items then
    U.error("Could not run git status.")
    return
  end
  local staged, unstaged, untracked = {}, {}, {}
  for _, it in ipairs(items) do
    if it.x == "?" then
      untracked[#untracked + 1] = it
    else
      if it.x ~= " " then
        staged[#staged + 1] = it
      end
      if it.y ~= " " then
        unstaged[#unstaged + 1] = it
      end
    end
  end
  local lines, targets = {}, {}
  local function add(text, path)
    lines[#lines + 1] = text
    if path then
      targets[#lines] = path
    end
  end
  add("Git: " .. (branch or "?"))
  add("Repository: " .. vim.fn.fnamemodify(r, ":~"))
  add("")
  local function section(title, list, code)
    add(("%s (%d)"):format(title, #list))
    for _, it in ipairs(list) do
      add(("  %s  %s"):format(code(it), it.path), r .. "/" .. it.path)
    end
    add("")
  end
  section("Staged", staged, function(it)
    return it.x
  end)
  section("Modified (unstaged)", unstaged, function(it)
    return it.y
  end)
  section("Untracked", untracked, function()
    return "?"
  end)
  add("Enter: open file · d: diff · q: close")
  if not U.has("lazygit") then
    add("Lazygit isn't installed; you can install it for advanced operations (optional).")
  end
  local buf, win = require("noctis.ui.float").text(lines, { title = "Git summary", ft = "noctis-git", width = 90 })
  local function target()
    return targets[api.nvim_win_get_cursor(win)[1]]
  end
  vim.keymap.set("n", "<CR>", function()
    local t = target()
    if t then
      api.nvim_win_close(win, true)
      vim.cmd("edit " .. vim.fn.fnameescape(t))
    end
  end, { buffer = buf })
  vim.keymap.set("n", "d", function()
    local t = target()
    if t then
      api.nvim_win_close(win, true)
      vim.cmd("edit " .. vim.fn.fnameescape(t))
      M.diff_file()
    end
  end, { buffer = buf })
end

function M.view()
  local ok, Snacks = pcall(require, "snacks")
  if U.has("lazygit") and ok and Snacks.lazygit and M.toplevel() then
    return Snacks.lazygit({ cwd = M.toplevel() })
  end
  M.summary()
end

function M.status()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker and not U.is_safe_mode() then
    if not M.toplevel() then
      U.info("This folder isn't a Git repository.")
      return
    end
    return Snacks.picker.git_status({ cwd = M.toplevel() })
  end
  M.summary()
end

--- File diff: left = the index (or HEAD) version, right = the working copy.
--- Never writes to the index or the working tree.
function M.diff_file()
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    U.info("Open a file to diff.")
    return
  end
  local r = M.toplevel(vim.fn.fnamemodify(path, ":h"))
  if not r then
    U.info("The file isn't in a Git repository.")
    return
  end
  local rel = U.relpath(r, path)
  local res = vim.system({ "git", "-C", r, "show", ":" .. rel }, { text = true }):wait(5000)
  local label = "index"
  if res.code ~= 0 then
    res = vim.system({ "git", "-C", r, "show", "HEAD:" .. rel }, { text = true }):wait(5000)
    label = "HEAD"
  end
  if res.code ~= 0 then
    U.info("The file isn't tracked by Git (new file); there's no version to compare with.")
    return
  end
  local text = res.stdout or ""
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  for i, l in ipairs(lines) do
    lines[i] = l:gsub("\r$", "")
  end
  vim.cmd("tab split")
  vim.cmd("diffthis")
  vim.wo.winbar = "%#NoctisAccent# WORKING COPY %#NoctisMuted# " .. rel
  vim.cmd("leftabove vnew")
  local scratch = api.nvim_get_current_buf()
  vim.bo[scratch].buflisted = false -- keep the temporary buffer out of the tab bar
  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  vim.cmd("diffthis")
  vim.wo.winbar = ("%%#NoctisWarning# GIT %s %%#NoctisMuted# read-only · ]c/[c: changes · :tabclose"):format(label:upper())
  vim.cmd("wincmd l")
end

function M.reset_hunk()
  if vim.fn.confirm("Reset the Git hunk under the cursor to the index version? (undo with u)", "&Yes\n&No", 2) == 1 then
    require("gitsigns").reset_hunk()
  end
end

return M
