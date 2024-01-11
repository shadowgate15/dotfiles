require('nvim-treesitter.configs').setup({
  modules = {},
  sync_install = false,
  auto_install = true,
  ensure_installed = {
    'comment',
    'jsdoc',
    'vimdoc',
  },
  ignore_install = {},
  highlight = {
    enable = true,
  },
  indent = {
    enable = true,
  },
})

-- https://github.com/JoosepAlviste/nvim-ts-context-commentstring/issues/82
require('nvim-treesitter.configs').setup({
  languages = {
    typescript = '// %s',
  },
})

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufAdd', 'BufNew', 'BufNewFile', 'BufWinEnter' }, {
  group = vim.api.nvim_create_augroup('TS_FOLD_WORKAROUND', {}),
  callback = function()
    vim.opt.foldmethod = 'expr'
    vim.opt.foldexpr = 'nvim_treesitter#foldexpr()'
  end,
})
