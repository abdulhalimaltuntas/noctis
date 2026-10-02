# Üçüncü taraf bileşenler

NOCTIS aşağıdaki bileşenlerin kaynak kodunu **içermez**; eklentiler
`noctis --setup` sırasında kendi depolarından, `app/lazy-lock.json`
dosyasındaki commit'lerle indirilir ve kendi lisanslarıyla dağıtılır.

| Bileşen | Kilitli sürüm | Lisans | Depo |
| --- | --- | --- | --- |
| Neovim | ≥ 0.12.0 (test: 0.12.4) — kullanıcı kurar | Apache-2.0 / Vim lisansı | https://github.com/neovim/neovim |
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

İsteğe bağlı harici araçlar (kullanıcı kurar; NOCTIS bunları dağıtmaz):
ripgrep, git, lazygit, tree-sitter CLI, dil sunucuları ve formatter'lar
(pyright, typescript-language-server, vscode-langservers-extracted,
lua-language-server, bash-language-server, ruff, prettier, stylua, shfmt),
AI CLI'leri (Claude Code, Codex CLI, Kimi Code).

Ekran görüntüleri üretilirken kullanılan Nerd Font sembol fontu
(Symbols Nerd Font, MIT) depoya dahil edilmemiştir.

Tasarım ve etkileşim fikirleri açısından LazyVim'den (Apache-2.0) ilham
alınmıştır; LazyVim kaynak kodu kopyalanmamıştır.
