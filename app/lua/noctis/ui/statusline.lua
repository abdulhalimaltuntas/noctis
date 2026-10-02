-- Global statusline: mod, kısaltılmış yol, Git, diagnostics, AI, konum.
-- Dar alanda ikincil bilgiler sırayla gizlenir.
local M = {}

local api = vim.api
local icons = require("noctis.ui.icons")

local modes = {
  n = { "NORMAL", "NoctisStNormal" },
  no = { "NORMAL", "NoctisStNormal" },
  nt = { "NORMAL", "NoctisStNormal" },
  v = { "VISUAL", "NoctisStVisual" },
  V = { "V-LINE", "NoctisStVisual" },
  ["\22"] = { "V-BLOCK", "NoctisStVisual" },
  s = { "SELECT", "NoctisStVisual" },
  S = { "SELECT", "NoctisStVisual" },
  i = { "INSERT", "NoctisStInsert" },
  ic = { "INSERT", "NoctisStInsert" },
  ix = { "INSERT", "NoctisStInsert" },
  R = { "REPLACE", "NoctisStReplace" },
  Rv = { "REPLACE", "NoctisStReplace" },
  c = { "COMMAND", "NoctisStCommand" },
  cv = { "COMMAND", "NoctisStCommand" },
  r = { "PROMPT", "NoctisStCommand" },
  rm = { "MORE", "NoctisStCommand" },
  ["r?"] = { "CONFIRM", "NoctisStCommand" },
  ["!"] = { "SHELL", "NoctisStTerminal" },
  t = { "TERMINAL", "NoctisStTerminal" },
}

-- Yeni başlayanlar için mod ipucu (geniş ekranda)
local hints = {
  NORMAL = "i: yaz · Space Space: komutlar",
  INSERT = "Esc: Normal moda dön",
  VISUAL = "y: kopyala · d: sil · Esc: bitir",
  ["V-LINE"] = "y: kopyala · d: sil · Esc: bitir",
  TERMINAL = "Ctrl-\\ e: editöre dön · Ctrl-\\ Ctrl-n: Normal",
}

local function hl(group, text)
  return "%#" .. group .. "#" .. text
end

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

local function width_of(parts)
  -- %#Grup# ve %< gibi öğeler hariç görünür genişlik
  local s = table.concat(parts):gsub("%%#[^#]*#", ""):gsub("%%%%", "%%"):gsub("%%<", "")
  return vim.fn.strdisplaywidth(s)
end

-- Özel buffer'lar için okunur adlar
local special_labels = {
  ["noctis-dashboard"] = "Başlangıç",
  ["noctis-changes"] = "AI · Değişiklikler",
  ["noctis-diff"] = "AI · Diff",
  ["noctis-replace"] = "Bul ve değiştir",
  ["noctis-info"] = "Bilgi",
  snacks_picker_list = "Gezgin",
  snacks_picker_input = "Arama",
  snacks_dashboard = "Başlangıç",
  help = "Yardım",
  checkhealth = "Sağlık kontrolü",
  lazy = "Eklentiler",
  mason = "Mason",
  qf = "Quickfix",
}

local function file_part(buf, maxw)
  local name = api.nvim_buf_get_name(buf)
  local bt = vim.bo[buf].buftype
  if bt == "terminal" then
    local label = vim.b[buf].noctis_label or "terminal"
    return hl("NoctisStFile", esc(label))
  elseif bt ~= "" or name == "" then
    local ft = vim.bo[buf].filetype
    if name == "" and bt == "" then
      return hl("NoctisStMuted", icons.get().file.unnamed)
    end
    return hl("NoctisStMuted", esc(special_labels[ft] or (ft ~= "" and ft or bt)))
  end
  local root = require("noctis.project").root()
  local rel = require("noctis.util").relpath(root, name) or vim.fn.fnamemodify(name, ":~")
  rel = require("noctis.util").shorten_path(rel, math.max(12, maxw))
  local dir, tail = rel:match("^(.*/)([^/]*)$")
  local out
  if dir then
    out = hl("NoctisStMuted", esc(dir)) .. hl("NoctisStFile", esc(tail))
  else
    out = hl("NoctisStFile", esc(rel))
  end
  local s = icons.get().file
  if vim.bo[buf].modified then
    out = out .. hl("NoctisStModified", " " .. s.modified)
  end
  if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
    out = out .. hl("NoctisStMuted", " " .. s.readonly)
  end
  return out
end

local function badges(buf)
  local out = {}
  local c = vim.b[buf].noctis_conflict
  if c then
    local label = ({ deleted = "SİLİNDİ", changed = "ÇATIŞMA", markers = "BİRLEŞTİR" })[c.reason] or "ÇATIŞMA"
    out[#out + 1] = hl("NoctisStConflict", " " .. label .. " ") .. hl("NoctisStText", " ")
  end
  if vim.b[buf].noctis_bigfile then
    out[#out + 1] = hl("NoctisStBadge", " BÜYÜK DOSYA ") .. hl("NoctisStText", " ")
  end
  return table.concat(out)
end

local function git_part(buf, compact)
  local d = vim.b[buf].gitsigns_status_dict
  local head = (d and d.head) or vim.b[buf].gitsigns_head
  if not head or head == "" then
    head = require("noctis.git").cached_branch()
  end
  if not head or head == "" then
    return ""
  end
  local g = icons.get().git
  local out = hl("NoctisStBranch", esc(g.branch .. head))
  if d and not compact then
    if (d.added or 0) > 0 then
      out = out .. hl("NoctisStAdded", " " .. g.added .. d.added)
    end
    if (d.changed or 0) > 0 then
      out = out .. hl("NoctisStChanged", " " .. g.changed .. d.changed)
    end
    if (d.removed or 0) > 0 then
      out = out .. hl("NoctisStRemoved", " " .. g.removed .. d.removed)
    end
  end
  return out
end

local function diag_part(buf)
  local counts = vim.diagnostic.count(buf)
  local sev = vim.diagnostic.severity
  local s = icons.get().diag
  local out = {}
  local e, w = counts[sev.ERROR] or 0, counts[sev.WARN] or 0
  local i, h = counts[sev.INFO] or 0, counts[sev.HINT] or 0
  if e > 0 then
    out[#out + 1] = hl("NoctisStError", vim.trim(s.error) .. " " .. e)
  end
  if w > 0 then
    out[#out + 1] = hl("NoctisStWarn", vim.trim(s.warn) .. " " .. w)
  end
  if i > 0 then
    out[#out + 1] = hl("NoctisStInfo", vim.trim(s.info) .. " " .. i)
  end
  if h > 0 then
    out[#out + 1] = hl("NoctisStHint", vim.trim(s.hint) .. " " .. h)
  end
  return table.concat(out, " ")
end

local function ai_part()
  if not package.loaded["noctis.ai"] then
    return ""
  end
  local ok, text = pcall(require("noctis.ai").status_text)
  if ok and text and text ~= "" then
    return hl("NoctisStAI", esc(text))
  end
  return ""
end

function M.render()
  local win = vim.g.statusline_winid or api.nvim_get_current_win()
  if not api.nvim_win_is_valid(win) then
    return ""
  end
  local buf = api.nvim_win_get_buf(win)
  local cols = vim.o.columns
  local m = modes[api.nvim_get_mode().mode] or { api.nvim_get_mode().mode:upper(), "NoctisStNormal" }
  local sep = hl("NoctisStSep", " " .. icons.get().ui.sep .. " ")

  local left = { hl(m[2], " " .. m[1] .. " "), hl("NoctisStText", " ") }
  left[#left + 1] = badges(buf)

  local right = {}
  local ai = ai_part()
  if ai ~= "" then
    right[#right + 1] = ai
  end
  local git = cols >= 70 and git_part(buf, cols < 110) or ""
  if git ~= "" then
    right[#right + 1] = git
  end
  local diag = diag_part(buf)
  if diag ~= "" then
    right[#right + 1] = diag
  end
  if cols >= 100 then
    local ft = vim.bo[buf].filetype
    if ft ~= "" and vim.bo[buf].buftype == "" then
      local extra = ft
      if vim.bo[buf].fileformat == "dos" then
        extra = extra .. " CRLF"
      end
      if vim.bo[buf].fileencoding ~= "" and vim.bo[buf].fileencoding ~= "utf-8" then
        extra = extra .. " " .. vim.bo[buf].fileencoding
      end
      right[#right + 1] = hl("NoctisStMuted", esc(extra))
    end
  end
  if vim.bo[buf].buftype == "" then
    local cur = api.nvim_win_get_cursor(win)
    right[#right + 1] = hl("NoctisStText", ("%d:%d"):format(cur[1], cur[2] + 1))
      .. hl("NoctisStDim", cols >= 90 and ("/%d"):format(api.nvim_buf_line_count(buf)) or "")
  end

  local right_s = table.concat(right, sep) .. hl("NoctisStText", " ")
  local avail = cols - width_of(left) - width_of({ right_s }) - 2
  left[#left + 1] = file_part(buf, avail - 2)

  -- Mod ipucu yalnız geniş ekranda ve rehber/ilk kullanım sürecinde
  if cols >= 140 and vim.g.noctis_show_hints then
    local hint = hints[m[1]]
    if hint and width_of(left) + width_of({ right_s }) + #hint + 6 < cols then
      left[#left + 1] = hl("NoctisStDim", "   " .. esc(hint))
    end
  end

  return table.concat(left) .. hl("NoctisStText", "%=") .. right_s
end

function M.title()
  local name = api.nvim_buf_get_name(0)
  local root = vim.fn.fnamemodify(require("noctis.project").root(), ":t")
  local brand = require("noctis.brand").name
  if name ~= "" and vim.bo.buftype == "" then
    return ("%s — %s · %s"):format(vim.fn.fnamemodify(name, ":t"), root, brand)
  end
  return ("%s · %s"):format(root, brand)
end

function M.setup()
  vim.o.statusline = "%!v:lua.require'noctis.ui.statusline'.render()"
  local group = api.nvim_create_augroup("noctis_statusline", { clear = true })
  api.nvim_create_autocmd({ "DiagnosticChanged", "ModeChanged", "User" }, {
    group = group,
    callback = function(ev)
      if ev.event ~= "User" or (ev.match:match("^Noctis") or ev.match == "GitSignsUpdate") then
        vim.cmd("redrawstatus")
      end
    end,
  })
end

return M
