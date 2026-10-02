# Third-party components

NOCTIS **does not include** the source code of the components below; plugins
are downloaded from their own repositories during `noctis --setup`, at the
commits in `app/lazy-lock.json`, and are distributed under their own licenses.

| Component | Pinned version | License | Repository |
| --- | --- | --- | --- |
| Neovim | ≥ 0.12.0 (tested: 0.12.4) — installed by the user | Apache-2.0 / Vim license | https://github.com/neovim/neovim |
| lazy.nvim | 85c7ff3 (v11.17.5) | Apache-2.0 | https://github.com/folke/lazy.nvim |
| snacks.nvim | 882c996 | Apache-2.0 | https://github.com/folke/snacks.nvim |
| which-key.nvim | 3aab214 | Apache-2.0 | https://github.com/folke/which-key.nvim |
| blink.cmp | 78336bc (v1.10.2) | MIT | https://github.com/saghen/blink.cmp |
| nvim-lspconfig | 3e8d598 | Apache-2.0 | https://github.com/neovim/nvim-lspconfig |
| nvim-treesitter (`main`) | 910fdf6 | Apache-2.0 | https://github.com/nvim-treesitter/nvim-treesitter |
| gitsigns.nvim | 070a5d7 | MIT | https://github.com/lewis6991/gitsigns.nvim |
| conform.nvim | 016802d | MIT | https://github.com/stevearc/conform.nvim |
| mason.nvim | 2a6940a | Apache-2.0 | https://github.com/mason-org/mason.nvim |
| mini.icons | f642e3b | MIT | https://github.com/nvim-mini/mini.icons |

Optional external tools (installed by the user; NOCTIS doesn't distribute them):
ripgrep, git, lazygit, the tree-sitter CLI, language servers and formatters
(pyright, typescript-language-server, vscode-langservers-extracted,
lua-language-server, bash-language-server, ruff, prettier, stylua, shfmt),
AI CLIs (Claude Code, Codex CLI, Kimi Code, OpenCode).

The Nerd Font symbols font used to render the screenshots (Symbols Nerd Font,
MIT) is not included in the repository.

Design and interaction ideas were inspired by LazyVim (Apache-2.0); no LazyVim
source code was copied.
