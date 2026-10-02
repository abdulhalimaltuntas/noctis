-- Fuzzy finder wrapper: uses snacks.picker when available; otherwise
-- (safe mode, missing plugin) it works with built-in Neovim tools.
local M = {}

local U = require("noctis.util")

local function snacks()
  if U.is_safe_mode() then
    return nil
  end
  local ok, S = pcall(require, "snacks")
  return ok and S.picker and S or nil
end

local function root()
  return require("noctis.project").root()
end

---@param opts? {hidden?:boolean, ignored?:boolean}
function M.files(opts)
  opts = opts or {}
  local S = snacks()
  if S then
    return S.picker.files({ cwd = root(), hidden = opts.hidden, ignored = opts.ignored, title = opts.ignored and "Files (all)" or "Files" })
  end
  vim.ui.input({ prompt = "File name (part): " }, function(q)
    if not q then
      return
    end
    local cmd = U.has("rg") and { "rg", "--files", "--color=never" } or { "find", ".", "-type", "f", "-not", "-path", "*/.git/*" }
    if U.has("rg") and opts.hidden then
      table.insert(cmd, "--hidden")
    end
    if U.has("rg") and opts.ignored then
      table.insert(cmd, "--no-ignore")
    end
    local res = vim.system(cmd, { cwd = root(), text = true }):wait(10000)
    local matches = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      if line:lower():find(q:lower(), 1, true) then
        matches[#matches + 1] = line:gsub("^%./", "")
        if #matches >= 300 then
          break
        end
      end
    end
    if #matches == 0 then
      U.info("No matching files.")
      return
    end
    vim.ui.select(matches, { prompt = "File" }, function(f)
      if f then
        vim.cmd("edit " .. vim.fn.fnameescape(root() .. "/" .. f))
      end
    end)
  end)
end

---@param opts? {hidden?:boolean, ignored?:boolean, word?:boolean}
function M.grep(opts)
  opts = opts or {}
  local S = snacks()
  if S then
    if opts.word then
      return S.picker.grep_word({ cwd = root() })
    end
    return S.picker.grep({ cwd = root(), hidden = opts.hidden, ignored = opts.ignored, title = opts.ignored and "Search project (all)" or "Search project" })
  end
  local function run(q)
    if not q or q == "" then
      return
    end
    local args = { "rg", "--vimgrep", "--smart-case", "--color=never" }
    if opts.hidden then
      args[#args + 1] = "--hidden"
    end
    if opts.ignored then
      args[#args + 1] = "--no-ignore"
    end
    args[#args + 1] = "--"
    args[#args + 1] = q
    local res = vim.system(args, { cwd = root(), text = true }):wait(30000)
    local lines = vim.split(res.stdout or "", "\n", { trimempty = true })
    vim.fn.setqflist({}, " ", { title = "Search: " .. q, lines = lines, efm = "%f:%l:%c:%m" })
    if #lines == 0 then
      U.info("No results.")
    else
      vim.cmd("botright copen")
    end
  end
  if opts.word then
    return run(vim.fn.expand("<cword>"))
  end
  vim.ui.input({ prompt = "Search project: " }, run)
end

function M.buffers()
  local S = snacks()
  if S then
    return S.picker.buffers()
  end
  local bufs = vim.tbl_filter(function(b)
    return vim.bo[b].buflisted
  end, vim.api.nvim_list_bufs())
  vim.ui.select(bufs, {
    prompt = "Buffer",
    format_item = function(b)
      local n = vim.api.nvim_buf_get_name(b)
      return (n == "" and "[No Name]" or vim.fn.fnamemodify(n, ":~:.")) .. (vim.bo[b].modified and " ●" or "")
    end,
  }, function(b)
    if b then
      vim.api.nvim_set_current_buf(b)
    end
  end)
end

function M.recent()
  local S = snacks()
  if S then
    return S.picker.recent()
  end
  local files = vim.tbl_filter(function(f)
    return vim.uv.fs_stat(f) ~= nil
  end, vim.list_slice(vim.v.oldfiles, 1, 50))
  vim.ui.select(files, { prompt = "Recent files", format_item = function(f)
    return vim.fn.fnamemodify(f, ":~:.")
  end }, function(f)
    if f then
      vim.cmd("edit " .. vim.fn.fnameescape(f))
    end
  end)
end

function M.lines()
  local S = snacks()
  if S then
    return S.picker.lines()
  end
  U.info("To search in this file, use the / key.")
  vim.api.nvim_feedkeys("/", "n", false)
end

---@param opts? {buffer?:boolean}
function M.diagnostics(opts)
  opts = opts or {}
  local S = snacks()
  if S then
    return opts.buffer and S.picker.diagnostics_buffer() or S.picker.diagnostics()
  end
  if opts.buffer then
    vim.diagnostic.setloclist({ open = true })
  else
    vim.diagnostic.setqflist({ open = true })
  end
end

---@param kind "definitions"|"references"|"symbols"
function M.lsp(kind)
  local S = snacks()
  if S then
    if kind == "definitions" then
      return S.picker.lsp_definitions()
    elseif kind == "references" then
      return S.picker.lsp_references()
    end
    return S.picker.lsp_symbols()
  end
  if kind == "definitions" then
    vim.lsp.buf.definition()
  elseif kind == "references" then
    vim.lsp.buf.references()
  else
    vim.lsp.buf.document_symbol()
  end
end

return M
