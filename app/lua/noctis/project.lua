-- Active project root and recent projects.
-- Root: the manually chosen one if set; otherwise the Git root; otherwise the working directory.
-- The working directory changes only when the user opens a project.
local M = {}

local U = require("noctis.util")

M.manual_root = nil ---@type string?
M.MAX_RECENT = 30

local markers = { ".git", ".hg", ".svn", ".jj" }

local function store()
  return U.state_dir() .. "/projects.json"
end

---@param path? string file or folder
---@return string root, string kind "manual"|"git"|"cwd"
function M.detect(path)
  if M.manual_root then
    return M.manual_root, "manual"
  end
  local start = path and path ~= "" and path or vim.fn.getcwd()
  local r = vim.fs.root(start, markers)
  if r then
    return U.norm(r), "git"
  end
  return U.norm(vim.fn.getcwd()), "cwd"
end

--- Active project root (cached; refreshed when cwd or the manual choice changes)
function M.root()
  if not M._root then
    M._root, M._kind = M.detect()
  end
  return M._root
end

function M.kind()
  M.root()
  return M._kind
end

function M.refresh()
  M._root, M._kind = nil, nil
  local r = M.root()
  M.touch(r)
  vim.api.nvim_exec_autocmds("User", { pattern = "NoctisRootChanged", modeline = false, data = { root = r } })
end

--- Add to the recent projects list
function M.touch(root)
  if not root or root == "" or root == vim.env.HOME or root == "/" then
    return
  end
  local list = U.json_read(store()) or {}
  local out = { { path = root, at = os.time() } }
  for _, p in ipairs(list) do
    if p.path ~= root and #out < M.MAX_RECENT then
      out[#out + 1] = p
    end
  end
  U.json_write(store(), out)
end

---@return {path:string, at:integer}[]
function M.recent()
  local out = {}
  for _, p in ipairs(U.json_read(store()) or {}) do
    if type(p) == "table" and p.path and vim.fn.isdirectory(p.path) == 1 then
      out[#out + 1] = p
    end
  end
  return out
end

--- Open a project: change the working directory and open the explorer.
function M.open(path)
  path = U.norm(vim.fn.expand(path))
  if vim.fn.isdirectory(path) == 0 then
    U.error("Folder not found: " .. path)
    return
  end
  M.manual_root = nil
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  M.refresh()
  U.info("Project: " .. vim.fn.fnamemodify(M.root(), ":~"))
  pcall(function()
    require("noctis.explorer").open()
  end)
end

function M.pick_recent()
  local list = M.recent()
  if #list == 0 then
    U.info("No recent projects yet. Open a folder: Space p o")
    return
  end
  vim.ui.select(list, {
    prompt = "Recent projects",
    format_item = function(p)
      return vim.fn.fnamemodify(p.path, ":~")
    end,
  }, function(p)
    if p then
      M.open(p.path)
    end
  end)
end

function M.open_prompt()
  vim.ui.input({ prompt = "Project folder: ", default = vim.fn.getcwd() .. "/", completion = "dir" }, function(input)
    if input and vim.trim(input) ~= "" then
      M.open(vim.trim(input))
    end
  end)
end

function M.set_root_prompt()
  vim.ui.input({ prompt = "Project root: ", default = M.root() .. "/", completion = "dir" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local p = U.norm(vim.fn.expand(vim.trim(input)))
    if vim.fn.isdirectory(p) == 0 then
      U.error("Folder not found: " .. p)
      return
    end
    M.manual_root = p
    M.refresh()
    U.info("Project root set manually: " .. vim.fn.fnamemodify(p, ":~"))
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("noctis_project", { clear = true })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      if not M.manual_root then
        M.refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      -- When opened with a file argument, the root is that file's Git root.
      local first = vim.fn.argv(0)
      if type(first) == "string" and first ~= "" and vim.fn.isdirectory(first) == 0 then
        local r = vim.fs.root(vim.fn.fnamemodify(first, ":p:h"), markers)
        if r and U.norm(r) ~= U.norm(vim.fn.getcwd()) then
          M._root, M._kind = U.norm(r), "git"
        end
      end
      M.touch(M.root())
    end,
  })
end

return M
