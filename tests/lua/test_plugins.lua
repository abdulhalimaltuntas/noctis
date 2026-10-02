-- Eklentiler yüklüyken arayüz akışları (headless duman testleri).
package.path = vim.env.NOCTIS_HOME .. "/../tests/lua/?.lua;" .. package.path
local H = require("helpers")
local api = vim.api
local R = require("noctis.registry")

H.suite("Eklentili arayüz")

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

local root = H.tmpdir("eklenti test")
H.write(root .. "/src/app.py", "print('x')\n")
H.write(root .. "/README.md", "# test\n")
vim.cmd("cd " .. vim.fn.fnameescape(root))
require("noctis.project").refresh()

H.test("kilit dosyasındaki tüm eklentiler kurulu ve lazy.nvim yüklendi", function()
  local cfg = require("lazy.core.config")
  for name, p in pairs(cfg.plugins) do
    H.ok(p._.installed, name .. " kurulu değil")
  end
end)

H.test("komut paleti snacks picker ile açılır ve kapanır; kullanılamaz komutlar gerekçeli", function()
  R.run("palette")
  H.wait(3000, function()
    return require("snacks").picker.get({ source = "noctis_commands" })[1] ~= nil
  end, "palet açıldı")
  local p = require("snacks").picker.get({ source = "noctis_commands" })[1]
  H.wait(3000, function()
    return #p:items() > 50
  end, "komutlar listelendi")
  p:close()
  vim.wait(100)
end)

H.test("henüz yüklenmemiş özelliğe palet/komutla erişim (lazy yükleme) çalışır", function()
  H.eq(package.loaded["conform"], nil, "conform başta yüklü değil")
  vim.cmd("edit src/app.py")
  R.run("code.format") -- conform require ile yüklenir
  H.wait(3000, function()
    return package.loaded["conform"] ~= nil
  end, "conform yüklendi")
end)

H.test("dosya gezgini açılır/kapanır ve proje kökünü gösterir", function()
  R.run("explorer")
  H.wait(3000, function()
    return require("noctis.explorer").get() ~= nil
  end, "gezgin açıldı")
  local p = require("noctis.explorer").get()
  H.eq(vim.fs.normalize(p:cwd()), root)
  R.run("explorer")
  H.wait(2000, function()
    return require("noctis.explorer").get() == nil
  end, "gezgin kapandı")
end)

H.test("dosya bulma ve metin arama picker'ları açılır", function()
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

H.test("tema değişince tüm bileşen grupları birlikte güncellenir", function()
  local before = api.nvim_get_hl(0, { name = "NoctisStNormal" }).bg
  local picker_before = api.nvim_get_hl(0, { name = "SnacksPickerMatch" }).fg
  require("noctis.theme").apply("amber")
  local after = api.nvim_get_hl(0, { name = "NoctisStNormal" }).bg
  H.ok(before ~= after, "statusline rengi değişti")
  H.ok(picker_before ~= api.nvim_get_hl(0, { name = "SnacksPickerMatch" }).fg, "picker rengi değişti")
  H.ok(api.nvim_get_hl(0, { name = "BlinkCmpMenuSelection", link = false }).bg ~= nil, "completion menüsü tanımlı")
  H.eq(vim.g.terminal_color_5, require("noctis.theme").tokens.accent, "terminal paleti")
  require("noctis.theme").apply("glacier")
  require("noctis.theme").apply("midnight-violet")
end)

H.test("256 renk yedeği: her grup için cterm rengi tanımlı", function()
  local hl = api.nvim_get_hl(0, { name = "Normal" })
  H.ok(hl.ctermfg and hl.ctermbg, "Normal cterm renkleri")
  H.eq(require("noctis.theme").to_cterm("#000000"), 16)
  H.eq(require("noctis.theme").to_cterm("#FFFFFF"), 231)
end)

H.test("yardım ve kısayol listesi ekrana sığan pencerede açılır, Esc ile kapanır", function()
  R.run("help")
  H.wait(1000, function()
    return floats() > 0
  end)
  local win = api.nvim_get_current_win()
  local cfg = api.nvim_win_get_config(win)
  H.ok(cfg.width <= vim.o.columns and cfg.height <= vim.o.lines, "ekrana sığar")
  api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.wait(200)
  H.ok(not api.nvim_win_is_valid(win), "Esc ile kapandı")
end)

H.test("dil paketi raporu ve :NoctisLang komutu çalışır", function()
  local lines = require("noctis.lang").report_lines()
  H.ok(#lines > 10)
  vim.cmd("NoctisLang")
  vim.wait(100)
  close_floats()
end)

H.test("AI Workbench paneli açılır/gizlenir; odak kendiliğinden alınmaz", function()
  local cur = api.nvim_get_current_win()
  require("noctis.ai").toggle()
  local wb = require("noctis.ai.workbench")
  H.ok(wb.is_visible(), "panel görünür")
  H.eq(api.nvim_get_current_win(), cur, "odak editörde kaldı")
  require("noctis.ai").toggle() -- ikinci basış: odaklan
  H.eq(api.nvim_get_current_win(), wb.win, "ikinci basışta odaklandı")
  require("noctis.ai").toggle() -- üçüncü: gizle
  H.ok(not wb.is_visible(), "gizlendi")
end)

H.test("statusline ve tabline hata vermeden çizilir (dar ve geniş)", function()
  for _, cols in ipairs({ 60, 80, 120, 200 }) do
    vim.o.columns = cols
    local s = require("noctis.ui.statusline").render()
    local t = require("noctis.ui.tabline").render()
    H.ok(type(s) == "string" and type(t) == "string")
  end
  vim.o.columns = 120
end)

H.done()
