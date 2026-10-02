-- Dil paketleri: her paket gereken dil sunucusunu, Tree-sitter parser'ını ve
-- formatter'ı açıkça tanımlar. Hiçbiri kendiliğinden indirilmez; kullanıcı
-- `:NoctisLang install <dil>` ile (Mason, ağ gerekir) veya sistem paket
-- yöneticisiyle kurar. Kurulu olmayan bileşen editörü bozmaz.
local M = {}

local U = require("noctis.util")

local prettier = { name = "prettier", exe = "prettier", mason = "prettier", hint = "npm i -g prettier" }

M.packs = {
  python = {
    label = "Python",
    filetypes = { "python" },
    servers = { { name = "pyright", exe = "pyright-langserver", mason = "pyright", hint = "npm i -g pyright  veya  pipx install pyright" } },
    formatters = { { name = "ruff_format", exe = "ruff", mason = "ruff", hint = "pipx install ruff" } },
    parsers = { "python" },
  },
  javascript = {
    label = "JavaScript / TypeScript",
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    servers = {
      { name = "ts_ls", exe = "typescript-language-server", mason = "typescript-language-server", hint = "npm i -g typescript typescript-language-server" },
    },
    formatters = { prettier },
    parsers = { "javascript", "typescript", "tsx" },
  },
  html = {
    label = "HTML / CSS",
    filetypes = { "html", "css", "scss", "less" },
    servers = {
      { name = "html", exe = "vscode-html-language-server", mason = "html-lsp", hint = "npm i -g vscode-langservers-extracted" },
      { name = "cssls", exe = "vscode-css-language-server", mason = "css-lsp", hint = "npm i -g vscode-langservers-extracted" },
    },
    formatters = { prettier },
    parsers = { "html", "css", "scss" },
  },
  json = {
    label = "JSON",
    filetypes = { "json", "jsonc" },
    servers = { { name = "jsonls", exe = "vscode-json-language-server", mason = "json-lsp", hint = "npm i -g vscode-langservers-extracted" } },
    formatters = { prettier },
    parsers = { "json" },
  },
  lua = {
    label = "Lua",
    filetypes = { "lua" },
    servers = { { name = "lua_ls", exe = "lua-language-server", mason = "lua-language-server", hint = "dağıtım paketi veya Mason" } },
    formatters = { { name = "stylua", exe = "stylua", mason = "stylua", hint = "cargo install stylua" } },
    parsers = { "lua" },
  },
  bash = {
    label = "Bash",
    filetypes = { "sh", "bash" },
    servers = { { name = "bashls", exe = "bash-language-server", mason = "bash-language-server", hint = "npm i -g bash-language-server" } },
    formatters = { { name = "shfmt", exe = "shfmt", mason = "shfmt", hint = "dağıtım paketi (shfmt)" } },
    parsers = { "bash" },
  },
}

M.order = { "python", "javascript", "html", "json", "lua", "bash" }

function M.names()
  return vim.deepcopy(M.order)
end

function M.enabled()
  local out = {}
  for _, name in ipairs(require("noctis.config").options.languages) do
    if M.packs[name] then
      out[#out + 1] = name
    else
      U.warn(("languages: bilinmeyen dil paketi `%s` (geçerli: %s)"):format(name, table.concat(M.order, ", ")))
    end
  end
  return out
end

M.mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

--- Mason ile kurulan araçlar, Mason yüklenmeden de bulunabilsin.
function M.setup_path()
  if vim.uv.fs_stat(M.mason_bin) and not (vim.env.PATH or ""):find(M.mason_bin, 1, true) then
    vim.env.PATH = M.mason_bin .. ":" .. (vim.env.PATH or "")
  end
end

function M.has_parser(lang)
  local ok, res = pcall(vim.treesitter.language.add, lang)
  return ok and res == true
end

---@return {server:table<string,boolean>, formatter:table<string,boolean>, parser:table<string,boolean>}
function M.status(name)
  local p = M.packs[name]
  local st = { server = {}, formatter = {}, parser = {} }
  for _, s in ipairs(p.servers) do
    st.server[s.name] = U.has(s.exe)
  end
  for _, f in ipairs(p.formatters) do
    st.formatter[f.name] = U.has(f.exe)
  end
  for _, l in ipairs(p.parsers) do
    st.parser[l] = M.has_parser(l)
  end
  return st
end

--- LSP kurulumu (nvim-lspconfig yüklendikten sonra çağrılır).
--- Yalnız executable'ı bulunan sunucular etkinleştirilir.
function M.setup_lsp()
  M.setup_path()
  local caps
  local ok, blink = pcall(require, "blink.cmp")
  if ok then
    caps = blink.get_lsp_capabilities()
  end
  vim.lsp.config("*", { capabilities = caps })
  vim.lsp.config("lua_ls", {
    settings = { Lua = { workspace = { checkThirdParty = false }, telemetry = { enable = false } } },
  })
  local enabled = {}
  for _, name in ipairs(M.enabled()) do
    for _, s in ipairs(M.packs[name].servers) do
      if U.has(s.exe) then
        enabled[#enabled + 1] = s.name
      end
    end
  end
  if #enabled > 0 then
    vim.lsp.enable(enabled)
  end
  M.active_servers = enabled
end

--- conform.nvim için formatters_by_ft
function M.formatters_by_ft()
  local out = {}
  for _, name in ipairs(M.enabled()) do
    local p = M.packs[name]
    local list = vim.tbl_map(function(f)
      return f.name
    end, p.formatters)
    list.stop_after_first = true
    for _, ft in ipairs(p.filetypes) do
      out[ft] = list
    end
  end
  return out
end

--- Tree-sitter: parser varsa vurgulamayı başlat (yoksa Vim regex syntax kalır)
function M.setup_treesitter()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("noctis_treesitter", { clear = true }),
    callback = function(ev)
      if vim.b[ev.buf].noctis_bigfile then
        return
      end
      local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
      if lang and M.has_parser(lang) then
        pcall(vim.treesitter.start, ev.buf, lang)
      end
    end,
  })
end

function M.report_lines()
  local ic = require("noctis.ui.icons").get().ui
  local lines = {
    "# Dil paketleri",
    "",
    "Hiçbir bileşen kendiliğinden indirilmez. Kurulum:",
    "  :NoctisLang install <dil>   Mason ile (ağ gerekir)   ·   veya satırdaki ipucu",
    "Tree-sitter parser'ı yoksa Vim'in yerleşik söz dizimi vurgusu kullanılır.",
    "",
  }
  local en = {}
  for _, n in ipairs(M.enabled()) do
    en[n] = true
  end
  for _, name in ipairs(M.order) do
    local p, st = M.packs[name], M.status(name)
    lines[#lines + 1] = ("## %s  (%s)%s"):format(p.label, name, en[name] and "" or "  — devre dışı (config: languages)")
    for _, s in ipairs(p.servers) do
      lines[#lines + 1] = ("  %s sunucu    %-28s %s"):format(st.server[s.name] and ic.check or ic.cross, s.exe, st.server[s.name] and "" or ("→ " .. s.hint))
    end
    for _, f in ipairs(p.formatters) do
      lines[#lines + 1] = ("  %s formatter %-28s %s"):format(st.formatter[f.name] and ic.check or ic.cross, f.exe, st.formatter[f.name] and "" or ("→ " .. f.hint))
    end
    local missing = {}
    for _, l in ipairs(p.parsers) do
      if not st.parser[l] then
        missing[#missing + 1] = l
      end
    end
    lines[#lines + 1] = ("  %s parser    %-28s %s"):format(
      #missing == 0 and ic.check or ic.cross,
      table.concat(p.parsers, ", "),
      #missing == 0 and "" or "→ :NoctisLang install " .. name .. " (tree-sitter CLI + C derleyici)"
    )
    lines[#lines + 1] = ""
  end
  return lines
end

function M.open()
  require("noctis.ui.float").text(M.report_lines(), { title = "Dil paketleri", ft = "markdown", width = 100 })
end

--- Mason + nvim-treesitter ile kurulum (kullanıcı başlatır, ağ gerekir)
function M.install(name)
  local p = M.packs[name]
  if not p then
    U.error("Bilinmeyen dil paketi: " .. tostring(name))
    return
  end
  local pkgs = {}
  for _, s in ipairs(p.servers) do
    if not U.has(s.exe) then
      pkgs[#pkgs + 1] = s.mason
    end
  end
  for _, f in ipairs(p.formatters) do
    if not U.has(f.exe) and not vim.tbl_contains(pkgs, f.mason) then
      pkgs[#pkgs + 1] = f.mason
    end
  end
  local summary = {}
  if #pkgs > 0 then
    summary[#summary + 1] = "Mason: " .. table.concat(pkgs, ", ")
  end
  local parsers = vim.tbl_filter(function(l)
    return not M.has_parser(l)
  end, p.parsers)
  local can_ts = U.has("tree-sitter") and (U.has("cc") or U.has("gcc") or U.has("clang"))
  if #parsers > 0 then
    summary[#summary + 1] = "Tree-sitter: " .. table.concat(parsers, ", ") .. (can_ts and "" or " (atlanacak: tree-sitter CLI veya C derleyici yok)")
  end
  if #summary == 0 then
    U.info(p.label .. ": tüm bileşenler zaten kurulu.")
    return
  end
  local msg = ("%s için indirilecekler:\n  %s\nAğ bağlantısı gerekir. Devam edilsin mi?"):format(p.label, table.concat(summary, "\n  "))
  if vim.fn.confirm(msg, "&Kur\n&Vazgeç", 2) ~= 1 then
    return
  end
  if #pkgs > 0 then
    local ok = pcall(require, "mason")
    if not ok then
      U.error("Mason kurulu değil (noctis --setup). Elle kurulum ipuçları: :NoctisLang")
    else
      vim.cmd("MasonInstall " .. table.concat(pkgs, " "))
    end
  end
  if #parsers > 0 and can_ts then
    local ok, ts = pcall(require, "nvim-treesitter")
    if ok then
      ts.install(parsers)
      U.info("Parser kurulumu arka planda başladı: " .. table.concat(parsers, ", "))
    end
  end
  U.info("Kurulum bittiğinde dosyayı yeniden açın (:e) veya NOCTIS'i yeniden başlatın.")
end

function M.command(args)
  if args[1] == "install" and args[2] then
    return M.install(args[2])
  end
  M.open()
end

return M
