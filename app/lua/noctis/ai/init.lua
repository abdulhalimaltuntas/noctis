-- AI Workbench public API (commands call into this module).
--
-- Separation: session/process management (sessions) and file change detection
-- (tracker/watcher/baseline) are independent of each other; tracking also works
-- when any external tool changes a file. Starting NOCTIS never launches an AI
-- tool on its own.
local M = {}

local U = require("noctis.util")
local api = vim.api

local function sessions()
  return require("noctis.ai.sessions")
end
local function wb()
  return require("noctis.ai.workbench")
end
local function tracker()
  return require("noctis.ai.tracker")
end

--- Project root shown by the Workbench: the active session's root, otherwise the active project.
function M.view_root()
  local s = package.loaded["noctis.ai.workbench"] and wb().current_session()
  if s then
    return s.root
  end
  return require("noctis.ai.review").root or require("noctis.project").root()
end

function M.toggle()
  require("noctis.ai.review").set_root(M.view_root())
  wb().toggle()
end

function M.hide()
  if package.loaded["noctis.ai.workbench"] then
    wb().hide()
  end
end

function M.focus()
  wb().open({ focus = true })
end

local function install_help(p)
  local lines = {
    ("# %s not found"):format(p.label),
    "",
    ("Command looked up: %s"):format(p.cmd[1]),
    "",
    "Install (the method from the official documentation):",
    "  " .. (p.install or "see the tool's documentation"),
    "",
    "Docs: " .. (p.docs or "-"),
    "",
    "If it lives somewhere else, set the path in config.lua:",
    ("  ai = { profiles = { %s = { cmd = { \"/full/path/%s\" } } } }"):format(p.name, p.cmd[1]),
    "",
    "Account login and permissions happen in the tool's own interface; NOCTIS stores no keys.",
  }
  require("noctis.ui.float").text(lines, { title = p.label, ft = "markdown" })
end

---@param opts? {resume?:boolean, profile?:string}
function M.new_session(opts)
  opts = opts or {}
  local P = require("noctis.ai.profiles")
  local all, order, errors = P.all()
  for _, e in ipairs(errors) do
    U.error("AI profile: " .. e)
  end
  local items = {}
  for _, name in ipairs(order) do
    local p = all[name]
    if not opts.resume or p.resume_args then
      items[#items + 1] = { p = p, exe = P.resolve(p) }
    end
  end
  if #items == 0 then
    U.warn("No suitable AI profile.")
    return
  end
  local function go(item)
    if not item.exe then
      return install_help(item.p)
    end
    M.start(item.p, opts)
  end
  if opts.profile then
    for _, it in ipairs(items) do
      if it.p.name == opts.profile then
        return go(it)
      end
    end
  end
  vim.ui.select(items, {
    prompt = opts.resume and "Tool whose previous session to resume" or "Pick an AI tool",
    format_item = function(it)
      local where = it.exe and vim.fn.fnamemodify(it.exe, ":~") or "not found — install help"
      return ("%-14s %s"):format(it.p.label, where)
    end,
  }, function(it)
    if it then
      go(it)
    end
  end)
end

--- Start the tool after the baseline has been recorded.
function M.start(profile, opts)
  opts = opts or {}
  local root = require("noctis.project").root()
  if root == vim.env.HOME or root == "/" then
    if vim.fn.confirm(("The project root is %s. Starting an AI tool here means a very wide scope; continue anyway?"):format(root), "&Yes\n&No", 2) ~= 1 then
      return
    end
  end
  local others = sessions().running(root)
  if #others > 0 then
    local names = table.concat(
      vim.tbl_map(function(s)
        return s.label
      end, others),
      ", "
    )
    local msg = ("An AI session is already running in this project: %s.\nConcurrent writes to the same working tree are risky; changes can't be attributed to individual tools.\nStart anyway?"):format(names)
    if vim.fn.confirm(msg, "&Start\n&Cancel", 2) ~= 1 then
      return
    end
  end
  require("noctis.ai.review").set_root(root)
  tracker().ensure(root, function()
    local win = wb().prepare_window()
    local s, err = sessions().start(profile, root, win, { resume = opts.resume })
    if not s then
      U.error(err or "failed to start")
      wb().show_view("changes", false)
      return
    end
    if err then
      U.error(err)
    end
    wb().show_view(s.id, true)
  end)
end

function M.switch()
  local list = sessions().list
  local items = { { id = "changes", label = "Changes (review interval)" } }
  for _, s in ipairs(list) do
    items[#items + 1] = { id = s.id, label = ("%d  %s  · %s  · %s"):format(s.n, s.label, sessions().status_text(s), vim.fn.fnamemodify(s.root, ":~")) }
  end
  vim.ui.select(items, {
    prompt = "AI view",
    format_item = function(it)
      return it.label
    end,
  }, function(it)
    if it then
      if it.id ~= "changes" then
        require("noctis.ai.review").set_root(sessions().get(it.id).root)
      end
      wb().show_view(it.id, it.id ~= "changes")
    end
  end)
end

function M.review()
  local root = M.view_root()
  require("noctis.ai.review").set_root(root)
  local t = tracker().get(root)
  if not t then
    -- Load the saved active interval if there is one; otherwise just show info without a new baseline
    if require("noctis.ai.store").active_id(root) then
      return tracker().ensure(root, function()
        wb().show_view("changes", true)
      end)
    end
  end
  wb().show_view("changes", true)
end

function M.new_interval()
  local root = M.view_root()
  local t = tracker().get(root)
  local msg = t
      and ("Close the active review interval and take a new baseline?\nNo files are changed; the current %d changes won't appear in the new interval (the old record is kept for the retention period)."):format(vim.tbl_count(t.changes))
    or "Take a new baseline for this project? (no files are changed)"
  if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
    return
  end
  require("noctis.ai.review").set_root(root)
  tracker().new_interval(root, function()
    if wb().is_visible() then
      wb().refresh()
    end
  end)
end

local function pick_session(filter, cb)
  local cur = package.loaded["noctis.ai.workbench"] and wb().current_session()
  if cur and filter(cur) then
    return cb(cur)
  end
  local list = vim.tbl_filter(filter, sessions().list)
  if #list == 0 then
    U.info("No suitable AI session.")
    return
  elseif #list == 1 then
    return cb(list[1])
  end
  vim.ui.select(list, {
    prompt = "AI session",
    format_item = function(s)
      return ("%d  %s · %s"):format(s.n, s.label, sessions().status_text(s))
    end,
  }, function(s)
    if s then
      cb(s)
    end
  end)
end

function M.stop()
  pick_session(sessions().alive, function(s)
    if vim.fn.confirm(("Stop the %s session? The process will be terminated."):format(s.label), "&Stop\n&Cancel", 2) == 1 then
      sessions().stop(s)
    end
  end)
end

function M.restart()
  pick_session(function()
    return true
  end, function(s)
    if sessions().alive(s) then
      if vim.fn.confirm(("%s is running. Stop and restart it?"):format(s.label), "&Yes\n&No", 2) ~= 1 then
        return
      end
    end
    local profile = require("noctis.ai.profiles").get(s.profile)
    if not profile then
      U.error("The profile is no longer defined: " .. s.profile)
      return
    end
    local root = s.root
    sessions().remove(s)
    local win = wb().prepare_window()
    local ns, err = sessions().start(profile, root, win, {})
    if ns then
      wb().show_view(ns.id, true)
    else
      U.error(err or "failed to start")
    end
  end)
end

function M.scope_info()
  local root = M.view_root()
  local t = tracker().get(root)
  if not t then
    U.info("No active review interval for this project (start a session with Space a n).")
    return
  end
  local iv = t.interval
  local by_reason = {}
  for rel, e in pairs(iv.files) do
    if e.reason then
      by_reason[e.reason] = by_reason[e.reason] or {}
      table.insert(by_reason[e.reason], rel)
    end
  end
  local labels = {
    large = "Large files (no content, only size/time are tracked)",
    sensitive = "Sensitive files (content is never copied)",
    limit = "Over the baseline limit (no content)",
    excluded = "User exclusions",
    symlink = "Symbolic links (not tracked)",
    unreadable = "Unreadable",
  }
  local s = iv.stats or {}
  local cfg = require("noctis.config").options.ai
  local lines = {
    "# Review scope",
    "",
    ("Project: %s"):format(vim.fn.fnamemodify(root, ":~")),
    ("Baseline: %s · method: %s"):format(os.date("%Y-%m-%d %H:%M:%S", iv.created_at), iv.method or "?"),
    ("Content recorded: %d files (%s) · out of scope: %d · took: %d ms"):format(s.captured or 0, U.human_size(s.bytes or 0), s.skipped or 0, s.ms or 0),
    s.limit_hit and ("Limit: " .. s.limit_hit) or "No limits were exceeded.",
    ("Limits: %s per file · %s total · at most %d files"):format(U.human_size(cfg.baseline.max_file_size), U.human_size(cfg.baseline.max_total_size), cfg.baseline.max_files),
    ("Watched directories: %d%s"):format(t.watcher:count(), t.watcher.overflow and " (limit exceeded; the rest are scanned periodically)" or ""),
    "Folders never watched: " .. table.concat(vim.tbl_keys(require("noctis.ai.scope").skip_dirs), ", "),
    ("Record store: %s (kept %d days, at most %d MB)"):format(require("noctis.ai.store").dir(root), cfg.retention_days, cfg.max_store_mb),
    "",
  }
  for reason, label in pairs(labels) do
    local list = by_reason[reason]
    if list then
      table.sort(list)
      lines[#lines + 1] = ("## %s (%d)"):format(label, #list)
      for i = 1, math.min(#list, 25) do
        lines[#lines + 1] = "  " .. list[i]
      end
      if #list > 25 then
        lines[#lines + 1] = ("  … and %d more files"):format(#list - 25)
      end
      lines[#lines + 1] = ""
    end
  end
  lines[#lines + 1] = "If out-of-scope files change, they show up in the list but can't be reverted since their previous content wasn't recorded."
  require("noctis.ui.float").text(lines, { title = "Review scope", ft = "markdown", width = 100 })
end

--- Prepare the selected code as AI context: shown first, never sent without confirmation.
function M.send_context()
  local mode = vim.fn.mode()
  local s_line, e_line
  if mode == "v" or mode == "V" or mode == "\22" then
    s_line, e_line = vim.fn.line("v"), vim.fn.line(".")
    if s_line > e_line then
      s_line, e_line = e_line, s_line
    end
    vim.cmd("normal! \27")
  else
    s_line, e_line = vim.fn.line("."), vim.fn.line(".")
  end
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  local rel = U.relpath(require("noctis.project").root(), path) or vim.fn.fnamemodify(path, ":~")
  local code = api.nvim_buf_get_lines(buf, s_line - 1, e_line, false)
  local text = ("%s:%d-%d\n```%s\n%s\n```\n"):format(rel, s_line, e_line, vim.bo[buf].filetype, table.concat(code, "\n"))
  pick_session(sessions().alive, function(s)
    local preview = vim.split(text, "\n", { plain = true })
    table.insert(preview, 1, ("Target: %s (%s). Enter: paste into the tool's input line (not sent) · q: cancel"):format(s.label, vim.fn.fnamemodify(s.root, ":~")))
    table.insert(preview, 2, "")
    local pbuf, pwin = require("noctis.ui.float").text(preview, { title = "Context preview", ft = "markdown", footer = " Enter: paste · q: cancel " })
    vim.keymap.set("n", "<CR>", function()
      api.nvim_win_close(pwin, true)
      if sessions().paste(s, text) then
        U.info("Context pasted into the tool's input line. Press Enter inside the tool to send it.")
        wb().show_view(s.id, true)
      end
    end, { buffer = pbuf })
  end)
end

--- Statusline summary
function M.status_text()
  if not package.loaded["noctis.ai.sessions"] and not package.loaded["noctis.ai.tracker"] then
    return ""
  end
  local root = require("noctis.project").root()
  local parts = {}
  local ic = require("noctis.ui.icons").get().ui.ai
  local live = package.loaded["noctis.ai.sessions"] and sessions().running() or {}
  if #live == 1 then
    parts[#parts + 1] = live[1].label .. " " .. live[1].status
  elseif #live > 1 then
    parts[#parts + 1] = #live .. " sessions"
  end
  local t = package.loaded["noctis.ai.tracker"] and tracker().get(root)
  if t then
    local n = vim.tbl_count(t.changes)
    if n > 0 then
      parts[#parts + 1] = n .. (n == 1 and " change" or " changes")
    end
  end
  if #parts == 0 then
    return ""
  end
  return vim.trim(ic) .. " " .. table.concat(parts, " · ")
end

--- Explorer mark: files changed in the interval
function M.explorer_mark(path)
  if not path or not package.loaded["noctis.ai.tracker"] then
    return nil
  end
  for root, t in pairs(tracker().by_root) do
    local rel = U.relpath(root, path)
    if rel and t.changes[rel] then
      local k = t.changes[rel].kind
      return {
        text = ({ added = "A", modified = "M", deleted = "D" })[k],
        hl = ({ added = "NoctisChangeAdded", modified = "NoctisChangeModified", deleted = "NoctisChangeDeleted" })[k],
      }
    end
  end
end

function M.setup()
  local group = api.nvim_create_augroup("noctis_ai", { clear = true })
  -- If there is an active interval (started earlier by a user action), keep tracking it.
  -- This doesn't start an AI tool.
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.defer_fn(function()
        local root = require("noctis.project").root()
        local ok, store = pcall(require, "noctis.ai.store")
        if ok and vim.uv.fs_stat(store.path(root) .. "/active.json") then
          local id = store.active_id(root)
          local iv = id and store.load_interval(root, id)
          if iv and not iv.closed_at then
            tracker().ensure(root, function() end)
            require("noctis.ai.review").set_root(root)
          end
        end
      end, 1500)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NoctisAIChanges",
    callback = function()
      -- Refresh the explorer marks
      local ok, explorer = pcall(require, "noctis.explorer")
      local p = ok and explorer.get()
      if p then
        pcall(function()
          require("snacks.explorer.actions").update(p, { refresh = true })
        end)
      end
    end,
  })
end

return M
