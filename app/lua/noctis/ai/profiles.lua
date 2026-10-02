-- AI CLI profilleri. Varsayılan komutlar bayraksız etkileşimli oturum açar.
-- Ek bayraklar yalnız aracın resmi belgelerinde doğrulanmış olanlardır:
--   Claude Code  claude --version · claude -c (dizindeki son konuşma)
--     https://code.claude.com/docs/en/cli-reference
--   Codex CLI    codex --version · codex resume --last
--     github.com/openai/codex (codex-rs/cli; developers.openai.com/codex/cli)
--   Kimi Code    kimi --version · kimi --continue (dizindeki son oturum)
--     https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html
-- NOCTIS API anahtarı saklamaz, araç izinlerini değiştirmez; oturum açma ve
-- izin istemleri aracın kendi arayüzünde kalır.
local M = {}

M.builtin = {
  claude = {
    label = "Claude Code",
    cmd = { "claude" },
    version_args = { "--version" },
    resume_args = { "--continue" },
    install = "curl -fsSL https://claude.ai/install.sh | bash   (veya: npm install -g @anthropic-ai/claude-code)",
    docs = "https://code.claude.com/docs/en/cli-reference",
  },
  codex = {
    label = "Codex CLI",
    cmd = { "codex" },
    version_args = { "--version" },
    resume_args = { "resume", "--last" },
    install = "npm install -g @openai/codex   (veya: brew install --cask codex)",
    docs = "https://developers.openai.com/codex/cli",
  },
  kimi = {
    label = "Kimi Code",
    cmd = { "kimi" },
    version_args = { "--version" },
    resume_args = { "--continue" },
    install = "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash   (veya: npm install -g @moonshot-ai/kimi-code)",
    docs = "https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html",
  },
}

M.order = { "claude", "codex", "kimi" }

local function valid_argv(v)
  if type(v) ~= "table" or #v == 0 then
    return false
  end
  for _, a in ipairs(v) do
    if type(a) ~= "string" then
      return false
    end
  end
  return true
end

--- Varsayılan + kullanıcı profilleri (kullanıcı alanları varsayılanı ezer)
---@return table<string, table>, string[] order, string[] errors
function M.all()
  local user = require("noctis.config").options.ai.profiles or {}
  local out, order, errors = {}, {}, {}
  for _, name in ipairs(M.order) do
    out[name] = vim.deepcopy(M.builtin[name])
    order[#order + 1] = name
  end
  local extra = vim.tbl_keys(user)
  table.sort(extra)
  for _, name in ipairs(extra) do
    local p = user[name]
    if p == false then
      out[name] = nil
      order = vim.tbl_filter(function(n)
        return n ~= name
      end, order)
    elseif type(p) ~= "table" then
      errors[#errors + 1] = ("ai.profiles.%s bir tablo olmalı"):format(name)
    else
      local merged = vim.tbl_extend("force", out[name] or {}, p)
      if not valid_argv(merged.cmd) then
        errors[#errors + 1] = ("ai.profiles.%s.cmd bir argüman dizisi olmalı, ör. { \"aider\", \"--no-auto-commits\" }"):format(name)
      else
        merged.label = merged.label or name
        out[name] = merged
        if not vim.tbl_contains(order, name) then
          order[#order + 1] = name
        end
      end
    end
  end
  for _, name in ipairs(order) do
    out[name].name = name
  end
  return out, order, errors
end

function M.get(name)
  return (M.all())[name]
end

--- Executable yolu (bulunamazsa nil)
function M.resolve(p)
  local exe = p.cmd[1]
  if exe:find("/") then
    return vim.fn.executable(exe) == 1 and exe or nil
  end
  local path = vim.fn.exepath(exe)
  return path ~= "" and path or nil
end

--- Sürüm sorgusu (AI görevi başlatmaz, ağ/ücretli çağrı yapmaz)
---@param cb fun(version:string?, err:string?)
function M.version(p, cb)
  local exe = M.resolve(p)
  if not exe then
    return cb(nil, "bulunamadı")
  end
  if not p.version_args then
    return cb(nil, "sürüm sorgusu tanımlı değil")
  end
  local cmd = { exe }
  vim.list_extend(cmd, p.version_args)
  local ok, err = pcall(vim.system, cmd, { text = true, timeout = 8000, env = require("noctis.util").child_env(), clear_env = true }, function(res)
    local text = vim.trim((res.stdout or "") .. (res.stdout == "" and (res.stderr or "") or ""))
    vim.schedule(function()
      if res.code == 0 then
        cb(text:match("[^\n]+"))
      else
        cb(nil, ("çıkış %s"):format(tostring(res.code)))
      end
    end)
  end)
  if not ok then
    cb(nil, tostring(err))
  end
end

return M
