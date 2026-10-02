-- :checkhealth noctis — the same checks as `noctis --doctor`.
local M = {}

function M.check()
  local h = vim.health
  for _, sec in ipairs(require("noctis.doctor").checks()) do
    h.start(sec.title)
    for _, it in ipairs(sec.items) do
      local advice = it.advice and { it.advice } or nil
      if it.level == "ok" then
        h.ok(it.msg)
      elseif it.level == "warn" then
        h.warn(it.msg, advice)
      elseif it.level == "error" then
        h.error(it.msg, advice)
      else
        h.info(it.msg .. (it.advice and ("  → " .. it.advice) or ""))
      end
    end
  end
  -- Information specific to the running session
  h.start("This session")
  local reg = require("noctis.registry")
  local problems = reg.conflicts()
  if #problems == 0 then
    h.ok(("%d commands, no keymap conflicts"):format(#reg.list))
  else
    for _, p in ipairs(problems) do
      h.warn(p)
    end
  end
  h.info("Clipboard: " .. require("noctis.clipboard").state)
  h.info(("termguicolors: %s · typing animation: %s"):format(tostring(vim.o.termguicolors), require("noctis.ui.typing").active() and "on" or "off"))
  if require("noctis.util").is_safe_mode() then
    h.warn("Safe mode: third-party plugins are disabled")
  end
end

return M
