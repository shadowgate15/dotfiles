local formatter = require('formatter')
local util = require('formatter.util')
local filetypes = require('formatter.filetypes')

formatter.setup({
  logging = true,
  log_level = vim.log.levels.WARN,
  filetype = {
    javascript = {
      filetypes.javascript.prettierd,
      filetypes.javascript.eslint_d,
    },
    javascriptreact = {
      filetypes.javascriptreact.prettierd,
      filetypes.javascriptreact.eslint_d,
    },
    lua = {
      filetypes.lua.stylua,
    },
    typescript = {
      filetypes.typescript.prettierd,
      filetypes.typescript.eslint_d,
    },
    typescriptreact = {
      filetypes.typescriptreact.prettierd,
      filetypes.typescriptreact.eslint_d,
    },
    ['*'] = {
      filetypes.any.remove_trailing_whitespace,
    },
  },
})

vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('AutoFormat', {}),
  callback = function()
    vim.cmd('FormatWrite')
  end,
})
