-- Komut kaydı: komut paleti, kısayollar, which-key grupları ve dokümantasyon
-- (docs/KEYMAPS.md) bu tek listeden beslenir.
local M = {}

---@class noctis.Command
---@field id string            benzersiz kimlik, ör. "files.find"
---@field title string         palette görünen ad
---@field desc? string         kısa açıklama
---@field group string         kategori (Dosya, Kod, AI ...)
---@field keys? string         varsayılan Normal mod kısayolu
---@field mode? string|string[] kısayol modu (varsayılan "n")
---@field run fun()            çalıştırılacak işlem
---@field check? fun():boolean,string?  kullanılabilirlik ve gerekçe
---@field palette? boolean     false ise palette gösterilmez

---@type noctis.Command[]
M.list = {}
---@type table<string, noctis.Command>
M.by_id = {}

-- which-key grupları (leader sonrası ilk tuş)
M.groups = {
  { "<leader>a", "AI Workbench" },
  { "<leader>b", "Buffer" },
  { "<leader>c", "Kod" },
  { "<leader>f", "Dosya / Bul" },
  { "<leader>g", "Git" },
  { "<leader>h", "Yardım / Sistem" },
  { "<leader>p", "Proje" },
  { "<leader>q", "Çıkış / Oturum" },
  { "<leader>s", "Ara / Değiştir" },
  { "<leader>t", "Terminal / Görev" },
  { "<leader>u", "Arayüz" },
  { "<leader>w", "Pencere" },
  { "<leader>x", "Tanılama" },
}

---@param spec noctis.Command
function M.add(spec)
  assert(spec.id and spec.title and spec.run and spec.group, "eksik komut alanı: " .. vim.inspect(spec.id))
  assert(not M.by_id[spec.id], "yinelenen komut kimliği: " .. spec.id)
  M.list[#M.list + 1] = spec
  M.by_id[spec.id] = spec
end

---@return boolean ok, string? reason
function M.available(cmd)
  if type(cmd) == "string" then
    cmd = M.by_id[cmd]
  end
  if not cmd then
    return false, "bilinmeyen komut"
  end
  if cmd.check then
    local ok, ok2, reason = pcall(cmd.check)
    if not ok then
      return false, tostring(ok2)
    end
    return ok2 ~= false, reason
  end
  return true
end

---@param id string
function M.run(id)
  local cmd = M.by_id[id]
  if not cmd then
    require("noctis.util").error("Bilinmeyen komut: " .. tostring(id))
    return
  end
  local ok, reason = M.available(cmd)
  if not ok then
    require("noctis.util").warn(("%s kullanılamıyor: %s"):format(cmd.title, reason or "gereksinim eksik"))
    return
  end
  local ok2, err = xpcall(cmd.run, debug.traceback)
  if not ok2 then
    require("noctis.util").log("ERROR", ("komut %s: %s"):format(id, err))
    require("noctis.util").error(("%s başarısız: %s"):format(cmd.title, tostring(err):match("^[^\n]*")))
  end
end

--- Kullanıcı override'larıyla etkin kısayol (false = devre dışı)
---@return string|false|nil
function M.effective_keys(cmd)
  local user = require("noctis.config").options.keymaps or {}
  if user[cmd.id] ~= nil then
    return user[cmd.id]
  end
  return cmd.keys
end

local function modes(cmd)
  local m = cmd.mode or "n"
  return type(m) == "table" and m or { m }
end

--- Aynı mod+tuş kombinasyonuna bağlanmış komutları ve prefix çakışmalarını bul.
---@return string[] problems
function M.conflicts()
  local seen, problems = {}, {}
  local leader = vim.g.mapleader or " "
  local function norm(lhs)
    return vim.api.nvim_replace_termcodes(lhs:gsub("<leader>", leader), true, true, true)
  end
  local all = {}
  for _, cmd in ipairs(M.list) do
    local keys = M.effective_keys(cmd)
    if keys then
      for _, mode in ipairs(modes(cmd)) do
        local k = mode .. "\0" .. norm(keys)
        if seen[k] then
          problems[#problems + 1] = ("%s (%s): `%s` ve `%s` aynı tuşu kullanıyor"):format(keys, mode, seen[k], cmd.id)
        else
          seen[k] = cmd.id
        end
        all[#all + 1] = { mode = mode, lhs = norm(keys), id = cmd.id, keys = keys }
      end
    end
  end
  -- Bir kısayol başka bir kısayolun öneki ise (ör. <leader>f ve <leader>ff),
  -- kısa olan beklemeye yol açar.
  for _, a in ipairs(all) do
    for _, b in ipairs(all) do
      if a ~= b and a.mode == b.mode and #a.lhs < #b.lhs and b.lhs:sub(1, #a.lhs) == a.lhs then
        problems[#problems + 1] = ("%s (%s) `%s`, `%s` için önek; bekleme gecikmesine yol açar"):format(
          a.keys,
          a.mode,
          a.id,
          b.id
        )
      end
    end
  end
  return problems
end

--- Kayıttaki tüm kısayolları uygula.
function M.apply_keymaps()
  for _, cmd in ipairs(M.list) do
    local keys = M.effective_keys(cmd)
    if keys then
      vim.keymap.set(modes(cmd), keys, function()
        M.run(cmd.id)
      end, { desc = cmd.title, silent = true })
    end
  end
  -- Kullanıcının override'da verdiği bilinmeyen kimlikleri bildir
  for id in pairs(require("noctis.config").options.keymaps or {}) do
    if not M.by_id[id] then
      require("noctis.util").warn(("keymaps: bilinmeyen komut kimliği `%s` (`:NoctisKeys` ile listeleyin)"):format(id))
    end
  end
end

--- Görünür adı için kısayolu biçimlendir: <leader>ff -> Space f f
function M.pretty_keys(keys)
  if not keys then
    return ""
  end
  local s = keys:gsub("<leader>", "Space "):gsub("<[Ll]ocalleader>", "\\ ")
  s = s:gsub("<[Cc]%-(.-)>", "Ctrl+%1 "):gsub("<[Ss]%-(.-)>", "Shift+%1 "):gsub("<[MmAa]%-(.-)>", "Alt+%1 ")
  s = s:gsub("<[Ss]pace>", "Space "):gsub("<[Ee]sc>", "Esc "):gsub("<[Cc][Rr]>", "Enter ")
  -- Space'ten sonraki tuşları ayır: "Space ff" -> "Space f f"
  s = s:gsub("^Space (%S+)", function(rest)
    if rest:find("^[%w%?/%.]+$") then
      return "Space " .. table.concat(vim.split(rest, ""), " ")
    end
    return "Space " .. rest
  end)
  return vim.trim(s:gsub("%s+", " "))
end

--- docs/KEYMAPS.md içeriğini üret
function M.markdown()
  local out = {
    "# NOCTIS kısayolları ve komutları",
    "",
    "> Bu dosya `app/lua/noctis/commands.lua` içindeki komut kaydından üretilir:",
    "> `noctis --headless` yerine `make docs` (veya `tests/gen-keymaps.sh`).",
    "",
    "Tüm komutlar `Space Space` komut paletinden adıyla aranabilir. Tablo Normal mod içindir.",
    "",
  }
  local by_group, order = {}, {}
  for _, cmd in ipairs(M.list) do
    if cmd.palette ~= false then
      if not by_group[cmd.group] then
        by_group[cmd.group] = {}
        order[#order + 1] = cmd.group
      end
      table.insert(by_group[cmd.group], cmd)
    end
  end
  for _, g in ipairs(order) do
    out[#out + 1] = "## " .. g
    out[#out + 1] = ""
    out[#out + 1] = "| Kısayol | Komut | Açıklama |"
    out[#out + 1] = "| --- | --- | --- |"
    for _, cmd in ipairs(by_group[g]) do
      local k = cmd.keys and ("`" .. M.pretty_keys(cmd.keys) .. "`") or "—"
      out[#out + 1] = ("| %s | %s | %s |"):format(k, cmd.title, (cmd.desc or ""):gsub("|", "\\|"))
    end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

return M
