-- Safe quit: shows unsaved buffers and running terminal/AI/task processes;
-- never kills anything blindly.
local M = {}

local api = vim.api

local function modified_bufs()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype ~= "terminal" then
      local name = api.nvim_buf_get_name(b)
      out[#out + 1] = { buf = b, label = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.") }
    end
  end
  return out
end

--- Running processes: shell terminals, AI sessions, tasks.
function M.running()
  local out = {}
  local ok_ai, ai = pcall(require, "noctis.ai.sessions")
  if ok_ai then
    for _, s in ipairs(ai.running()) do
      out[#out + 1] = ("AI: %s (%s)"):format(s.label, s.status)
    end
  end
  local ok_t, term = pcall(require, "noctis.terminal")
  if ok_t then
    for _, t in ipairs(term.running()) do
      out[#out + 1] = "Terminal: " .. t
    end
  end
  local ok_k, tasks = pcall(require, "noctis.tasks")
  if ok_k then
    for _, t in ipairs(tasks.running()) do
      out[#out + 1] = "Task: " .. t
    end
  end
  return out
end

function M.quit()
  local mods = modified_bufs()
  local procs = M.running()
  if #mods == 0 and #procs == 0 then
    vim.cmd("qa")
    return
  end
  local lines = {}
  if #mods > 0 then
    lines[#lines + 1] = "Unsaved files:"
    for _, m in ipairs(mods) do
      lines[#lines + 1] = "  • " .. m.label
    end
  end
  if #procs > 0 then
    lines[#lines + 1] = "Running processes (stopped on quit, nothing keeps running in the background):"
    for _, p in ipairs(procs) do
      lines[#lines + 1] = "  • " .. p
    end
  end
  local buttons, actions = {}, {}
  if #mods > 0 then
    buttons[#buttons + 1] = "&Save and quit"
    actions[#actions + 1] = function()
      require("noctis.files").save_all()
      if #modified_bufs() > 0 then
        require("noctis.util").warn("Some files could not be saved; quit cancelled.")
        return
      end
      vim.cmd("qa!")
    end
    buttons[#buttons + 1] = "&Quit without saving (changes are lost)"
    actions[#actions + 1] = function()
      vim.cmd("qa!")
    end
  else
    buttons[#buttons + 1] = "&End processes and quit"
    actions[#actions + 1] = function()
      vim.cmd("qa!")
    end
  end
  buttons[#buttons + 1] = "&Cancel"
  local choice = vim.fn.confirm(table.concat(lines, "\n"), table.concat(buttons, "\n"), #buttons)
  if actions[choice] then
    actions[choice]()
  end
end

return M
