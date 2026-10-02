-- lazy.nvim bootstrap.
-- A normal launch makes no network requests: if lazy.nvim or plugins are
-- missing, the editor opens in basic mode and points the user to `noctis --setup`.
local M = {}

local U = require("noctis.util")

M.lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
M.lockfile = require("noctis.brand").home .. "/lazy-lock.json"

local function read_lock()
  return U.json_read(M.lockfile) or {}
end

--- In setup mode, clone lazy.nvim at the commit from the lockfile.
function M.bootstrap()
  if vim.uv.fs_stat(M.lazypath) then
    return true
  end
  local lock = read_lock()
  local commit = lock["lazy.nvim"] and lock["lazy.nvim"].commit
  local branch = lock["lazy.nvim"] and lock["lazy.nvim"].branch or "stable"
  io.stdout:write(("• downloading lazy.nvim (%s)\n"):format(commit and commit:sub(1, 7) or branch))
  local res = vim
    .system({ "git", "clone", "--filter=blob:none", "--branch=" .. branch, "https://github.com/folke/lazy.nvim.git", M.lazypath }, { text = true })
    :wait(180000)
  if res.code ~= 0 then
    io.stderr:write("could not download lazy.nvim:\n" .. (res.stderr or "") .. "\n")
    vim.fn.delete(M.lazypath, "rf")
    return false
  end
  if commit then
    vim.system({ "git", "-C", M.lazypath, "checkout", "-q", commit }):wait(60000)
  end
  return true
end

---@return boolean loaded
function M.setup()
  local setup_mode = vim.env.NOCTIS_SETUP == "1"
  if not vim.uv.fs_stat(M.lazypath) then
    if setup_mode then
      if not M.bootstrap() then
        return false
      end
    else
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          U.warn(
            "Plugins are not installed yet; running in basic mode.\n"
              .. "To install, run in a terminal: noctis --setup  (needs network)\n"
              .. "Details: noctis --doctor"
          )
        end,
      })
      return false
    end
  end
  vim.opt.rtp:prepend(M.lazypath)

  local icons = require("noctis.ui.icons")
  require("lazy").setup({
    spec = { { import = "noctis.plugins" } },
    lockfile = M.lockfile,
    defaults = { lazy = true },
    -- Missing plugins are installed only by `noctis --setup`.
    install = { missing = setup_mode, colorscheme = {} },
    checker = { enabled = false }, -- no background update checks
    change_detection = { enabled = false },
    rocks = { enabled = false },
    ui = {
      border = icons.border_opt(),
      title = " NOCTIS plugins ",
      icons = not icons.enabled() and {
        cmd = ":",
        config = "cfg",
        event = "ev",
        favorite = "*",
        ft = "ft",
        init = "init",
        import = "imp",
        keys = "key",
        lazy = "z",
        loaded = "+",
        not_loaded = "-",
        plugin = "",
        runtime = "rt",
        require = "req",
        source = "src",
        start = ">",
        task = "~",
        list = { "*", "-", "+", "." },
      } or nil,
    },
    performance = {
      rtp = {
        reset = true,
        paths = { require("noctis.brand").home },
        disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin", "netrwPlugin" },
      },
    },
  })

  if not setup_mode then
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        local missing = {}
        for name, p in pairs(require("lazy.core.config").plugins) do
          if not p._.installed then
            missing[#missing + 1] = name
          end
        end
        if #missing > 0 then
          table.sort(missing)
          U.warn(("%d plugins are not installed: %s\nTo install: noctis --setup"):format(#missing, table.concat(missing, ", ")))
        end
      end,
    })
  end
  return true
end

return M
