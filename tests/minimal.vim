set rtp +=.
set rtp +=~/.local/share/nvim/lazy/plenary.nvim/
set rtp +=~/.local/share/nvim/lazy/nvim-treesitter/

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.lua

set noswapfile
set nobackup

filetype indent off
set nowritebackup
set noautoindent
set nocindent
set nosmartindent
set indentexpr=
set foldlevel=9999

lua << EOF
local ts_filetypes = {
  'html', 'javascript', 'typescript', 'svelte', 'vue', 'tsx', 'php', 'glimmer', 'embedded_template'
}
require("plenary/busted")
vim.cmd[[luafile ./tests/test-utils.lua]]
require("nvim-ts-autotag").setup({
    enable = true,
    enable_rename = true,
    enable_close = true,
    enable_close_on_slash = true,
})

require("nvim-treesitter.configs").setup({
    ensure_installed = ts_filetypes,
})
EOF
