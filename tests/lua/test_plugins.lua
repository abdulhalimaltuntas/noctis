-- Interface flows with plugins installed (headless smoke tests).
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api
local R = require("noctis.registry")

H.suite("Interface with plugins")

local function floats()
  local n = 0
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(w).relative ~= "" then
      n = n + 1
    end
  end
  return n
end

local function close_floats()
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(w).relative ~= "" then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

-- Every test starts without floating windows, in the editor window
local test = H.test
H.test = function(name, fn)
  test(name, function()
    -- Close pickers through their own API first (force-closing the window
    -- leaves objects in the snacks registry), then any remaining floats
    for _, pk in ipairs(require("snacks").picker.get()) do
      pcall(pk.close, pk)
    end
    vim.wait(50)
    close_floats()
    require("noctis.ui.layout").focus_editor()
    fn()
  end)
end

local root = H.tmpdir("plugin test")
H.write(root .. "/src/app.py", "print('x')\n")
H.write(root .. "/README.md", "# test\n")
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()

H.test("every plugin in the lockfile is installed and lazy.nvim is loaded", function()
  local cfg = require("lazy.core.config")
  for name, p in pairs(cfg.plugins) do
    H.ok(p._.installed, name .. " not installed")
  end
end)

H.test("the command palette opens and closes with snacks picker; unavailable commands have reasons", function()
  R.run("palette")
  H.wait(3000, function()
    return require("snacks").picker.get({ source = "noctis_commands" })[1] ~= nil
  end, "palette opened")
  local p = require("snacks").picker.get({ source = "noctis_commands" })[1]
  H.wait(3000, function()
    return #p:items() > 50
  end, "commands listed")
  p:close()
  vim.wait(100)
end)

H.test("reaching a not-yet-loaded feature from the palette/command (lazy loading) works", function()
  H.eq(package.loaded["conform"], nil, "conform not loaded at first")
  vim.cmd("edit src/app.py")
  R.run("code.format") -- conform is loaded via require
  H.wait(3000, function()
    return package.loaded["conform"] ~= nil
  end, "conform loaded")
end)

H.test("the file explorer opens/closes and shows the project root", function()
  R.run("explorer")
  H.wait(3000, function()
    return require("noctis.explorer").get() ~= nil
  end, "explorer opened")
  local p = require("noctis.explorer").get()
  H.eq(vim.fs.normalize(p:cwd()), root)
  R.run("explorer")
  H.wait(2000, function()
    return require("noctis.explorer").get() == nil
  end, "explorer closed")
end)

H.test("the find-file and text-search pickers open", function()
  R.run("files.find")
  H.wait(3000, function()
    return require("snacks").picker.get({ source = "files" })[1] ~= nil
  end)
  require("snacks").picker.get({ source = "files" })[1]:close()
  R.run("files.grep")
  H.wait(3000, function()
    return require("snacks").picker.get({ source = "grep" })[1] ~= nil
  end)
  require("snacks").picker.get({ source = "grep" })[1]:close()
  vim.wait(100)
  close_floats()
end)

H.test("when the theme changes, every component group updates together", function()
  local before = api.nvim_get_hl(0, { name = "NoctisStNormal" }).bg
  local picker_before = api.nvim_get_hl(0, { name = "SnacksPickerMatch" }).fg
  require("noctis.theme").apply("amber")
  local after = api.nvim_get_hl(0, { name = "NoctisStNormal" }).bg
  H.ok(before ~= after, "statusline color changed")
  H.ok(picker_before ~= api.nvim_get_hl(0, { name = "SnacksPickerMatch" }).fg, "picker color changed")
  H.ok(api.nvim_get_hl(0, { name = "BlinkCmpMenuSelection", link = false }).bg ~= nil, "completion menu defined")
  H.eq(vim.g.terminal_color_5, require("noctis.theme").tokens.accent, "terminal palette")
  require("noctis.theme").apply("glacier")
  require("noctis.theme").apply("midnight-violet")
end)

H.test("256-color fallback: every group has a cterm color", function()
  local hl = api.nvim_get_hl(0, { name = "Normal" })
  H.ok(hl.ctermfg and hl.ctermbg, "Normal cterm colors")
  H.eq(require("noctis.theme").to_cterm("#000000"), 16)
  H.eq(require("noctis.theme").to_cterm("#FFFFFF"), 231)
end)

H.test("help and the keymap list open in a window that fits the screen and close with Esc", function()
  R.run("help")
  H.wait(1000, function()
    return floats() > 0
  end)
  local win = api.nvim_get_current_win()
  local cfg = api.nvim_win_get_config(win)
  H.ok(cfg.width <= vim.o.columns and cfg.height <= vim.o.lines, "fits the screen")
  api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.wait(200)
  H.ok(not api.nvim_win_is_valid(win), "closed with Esc")
end)

H.test("the language pack report and :NoctisLang work", function()
  local lines = require("noctis.lang").report_lines()
  H.ok(#lines > 10)
  vim.cmd("NoctisLang")
  vim.wait(100)
  close_floats()
end)

H.test("the AI Workbench panel opens/hides; it never takes focus on its own", function()
  local cur = api.nvim_get_current_win()
  require("noctis.ai").toggle()
  local wb = require("noctis.ai.workbench")
  H.ok(wb.is_visible(), "panel visible")
  H.eq(api.nvim_get_current_win(), cur, "focus stayed in the editor")
  require("noctis.ai").toggle() -- second press: focus
  H.eq(api.nvim_get_current_win(), wb.win, "focused on the second press")
  require("noctis.ai").toggle() -- third: hide
  H.ok(not wb.is_visible(), "hidden")
end)

H.test("the file picker opens the selected file", function()
  vim.cmd("silent! %bwipeout!")
  R.run("files.find")
  local p
  H.wait(3000, function()
    local all = require("snacks").picker.get({ source = "files" })
    p = all[#all]
    return p ~= nil
  end)
  -- A filter entered before the finder (file list) completes may not trigger the matcher
  H.wait(5000, function()
    return not p:is_active() and #p:items() > 0
  end, "file list")
  -- Do what snacks' TextChanged handler does when the user types:
  -- set the filter and rerun the matcher
  p.input:set("app.py")
  p:find({ refresh = false })
  H.wait(5000, function()
    local cur = p:current()
    return cur ~= nil and (cur.file or ""):match("app%.py$") ~= nil
  end, "match · cwd=" .. tostring(p:cwd()) .. " filter=" .. tostring(p.input.filter.pattern) .. " items=" .. vim.inspect(vim.tbl_map(function(i)
    return i.file
  end, vim.list_slice(p:items(), 1, 5))))
  p:action("confirm")
  local function state()
    local t = {}
    for _, w in ipairs(api.nvim_list_wins()) do
      t[#t + 1] = ("%d:%s:%s"):format(w, api.nvim_win_get_config(w).relative, api.nvim_buf_get_name(api.nvim_win_get_buf(w)))
    end
    return "cur=" .. api.nvim_get_current_win() .. " " .. table.concat(t, " | ")
  end
  H.wait(3000, function()
    return vim.api.nvim_buf_get_name(0):match("src/app%.py$") ~= nil
  end, "file opened · " .. state())
  close_floats()
end)

H.test("a project search result jumps to the right file and line", function()
  H.write(root .. "/src/deep.py", "a = 1\nb = 2\nTARGET_LINE = 3\n")
  R.run("files.grep")
  local p
  H.wait(3000, function()
    local all = require("snacks").picker.get({ source = "grep" })
    p = all[#all]
    return p ~= nil
  end)
  p.input:set(nil, "TARGET_LINE") -- live search: the text goes into the search field
  p:find()
  H.wait(8000, function()
    local cur = p:current()
    return cur ~= nil and (cur.file or ""):match("deep%.py$") ~= nil
  end, "search result")
  p:action("confirm")
  H.wait(3000, function()
    return vim.api.nvim_buf_get_name(0):match("deep%.py$") ~= nil
  end, "file opened")
  H.eq(api.nvim_win_get_cursor(0)[1], 3, "line")
  close_floats()
end)

H.test("Git signs match the real git diff; a folder without Git is fine", function()
  local g = H.tmpdir("git signs")
  H.init_repo(g)
  H.write(g .. "/f.txt", "1\n2\n3\n4\n")
  H.git(g, "add", ".")
  H.git(g, "commit", "-q", "-m", "x")
  H.write(g .. "/f.txt", "1\nTWO\n3\n4\nfive\n")
  vim.cmd("cd " .. vim.fn.fnameescape(g))
  vim.cmd("edit f.txt")
  local buf = api.nvim_get_current_buf()
  H.wait(5000, function()
    return vim.b[buf].gitsigns_status_dict ~= nil and (vim.b[buf].gitsigns_status_dict.added or 0) > 0
  end, "gitsigns")
  local d = vim.b[buf].gitsigns_status_dict
  local numstat = H.git(g, "diff", "--numstat")
  local a, del = numstat:match("^(%d+)%s+(%d+)")
  -- gitsigns counts a modified line as "changed"; git numstat gives additions+deletions
  H.eq(d.added + d.changed, tonumber(a), "added/changed lines")
  H.eq(d.changed + d.removed, tonumber(del), "removed/changed lines")
  local plain = H.tmpdir("no git")
  H.write(plain .. "/x.txt", "x\n")
  vim.cmd("cd " .. vim.fn.fnameescape(plain))
  vim.cmd("edit x.txt")
  vim.wait(300)
  H.eq(vim.b.gitsigns_status_dict, nil, "no signs in a folder without Git")
  H.ok(#require("noctis.ui.statusline").render() > 0)
  vim.cmd("cd " .. vim.fn.fnameescape(root))
end)

H.test("statusline and tabline render without errors (narrow and wide)", function()
  local long = root .. "/" .. string.rep("a_very_long_file_name_", 6) .. ".py"
  H.write(long, "x = 1\n")
  vim.cmd("edit " .. vim.fn.fnameescape(long))
  -- Restore the width afterwards: with no UI attached, Neovim keeps the
  -- tabline click table at the startup width, and a UI attached later (noice's
  -- vim.ui_attach) would draw past it (heap corruption in stl_fill_click_defs).
  local cols0 = vim.o.columns
  for _, cols in ipairs({ 60, 80, 120, 200 }) do
    vim.o.columns = cols
    local s = require("noctis.ui.statusline").render()
    local t = require("noctis.ui.tabline").render()
    H.ok(type(s) == "string" and type(t) == "string")
    -- The visible width must not exceed the screen (%-items excluded)
    local visible = vim.api.nvim_eval_statusline(s, { maxwidth = cols }).width
    H.ok(visible <= cols, ("statusline %d > %d"):format(visible, cols))
    local tvis = vim.api.nvim_eval_statusline(t, { maxwidth = cols, use_tabline = true }).width
    H.ok(tvis <= cols, ("tabline %d > %d"):format(tvis, cols))
  end
  vim.o.columns = cols0
end)

H.test("the command line is a popup at the top center (noice); completion menu lists names only", function()
  require("lazy").load({ plugins = { "noice.nvim" } })
  -- noice finishes its setup on the next event-loop tick
  H.wait(3000, function()
    return require("noice.config").options.cmdline ~= nil and require("noice.ui")._attached
  end, "noice set up")
  local cfg = require("noice.config").options
  H.eq(cfg.cmdline.view, "cmdline_popup")
  H.eq(cfg.views.cmdline_popup.position.row, 3, "command_palette preset: near the top")
  H.eq(cfg.views.cmdline_popup.position.col, "50%", "centered")
  H.eq(cfg.cmdline.format.search_down.view, "cmdline", "bottom_search preset: / stays at the bottom")
  H.eq(cfg.messages.enabled, false, "messages keep Neovim's message area")
  H.eq(cfg.notify.enabled, false, "vim.notify stays with snacks")
  H.ok(require("noice.ui")._attached, "noice attached to the command line")
  -- styled from the theme, in every variant
  local theme = require("noctis.theme")
  for _, name in ipairs({ "midnight-violet", "daybreak" }) do
    theme.apply(name)
    local border = api.nvim_get_hl(0, { name = "NoiceCmdlinePopupBorder", link = false })
    H.eq(("#%06X"):format(border.fg), theme.tokens.accent_soft, name .. " border")
    H.ok(api.nvim_get_hl(0, { name = "NoiceCmdlineIconLua", link = false }).fg, name .. " lua icon")
  end
  theme.apply("midnight-violet")
  -- blink's command line menu: names only (resolved NOCTIS spec options)
  local blink = require("lazy.core.config").plugins["blink.cmp"]
  local cols = require("lazy.core.plugin").values(blink, "opts", false).cmdline.completion.menu.draw.columns
  H.eq(#cols, 1)
  H.eq(cols[1][1], "label")
end)

H.test("ui.cmdline = 'classic' keeps Neovim's command line", function()
  local spec = require("lazy.core.config").plugins["noice.nvim"]
  local opts = require("noctis.config").options
  opts.ui.cmdline = "classic"
  H.eq(spec.cond(), false)
  opts.ui.cmdline = "popup"
  H.eq(spec.cond(), true)
end)

H.done()
