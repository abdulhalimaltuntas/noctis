-- Aktif proje kökü ve son projeler.
-- Kök: elle seçilmişse o; değilse Git kökü; o da yoksa çalışma klasörü.
-- Çalışma klasörü yalnız kullanıcı bir proje açtığında değiştirilir.
local M = {}

local U = require("noctis.util")

M.manual_root = nil ---@type string?
M.MAX_RECENT = 30

local markers = { ".git", ".hg", ".svn", ".jj" }

local function store()
  return U.state_dir() .. "/projects.json"
end

---@param path? string dosya veya klasör
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

--- Aktif proje kökü (önbellekli; cwd veya elle seçim değişince yenilenir)
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

--- Son projeler listesine ekle
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

--- Bir projeyi aç: çalışma klasörünü değiştir ve gezgini aç.
function M.open(path)
  path = U.norm(vim.fn.expand(path))
  if vim.fn.isdirectory(path) == 0 then
    U.error("Klasör bulunamadı: " .. path)
    return
  end
  M.manual_root = nil
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  M.refresh()
  U.info("Proje: " .. vim.fn.fnamemodify(M.root(), ":~"))
  pcall(function()
    require("noctis.explorer").open()
  end)
end

function M.pick_recent()
  local list = M.recent()
  if #list == 0 then
    U.info("Henüz son proje yok. Bir klasör açın: Space p o")
    return
  end
  vim.ui.select(list, {
    prompt = "Son projeler",
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
  vim.ui.input({ prompt = "Proje klasörü: ", default = vim.fn.getcwd() .. "/", completion = "dir" }, function(input)
    if input and vim.trim(input) ~= "" then
      M.open(vim.trim(input))
    end
  end)
end

function M.set_root_prompt()
  vim.ui.input({ prompt = "Proje kökü: ", default = M.root() .. "/", completion = "dir" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local p = U.norm(vim.fn.expand(vim.trim(input)))
    if vim.fn.isdirectory(p) == 0 then
      U.error("Klasör bulunamadı: " .. p)
      return
    end
    M.manual_root = p
    M.refresh()
    U.info("Proje kökü elle ayarlandı: " .. vim.fn.fnamemodify(p, ":~"))
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
      -- Dosya argümanıyla açıldıysa kök, dosyanın Git köküdür.
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
