local builtins = require('telescope.builtin')

require('telescope').setup({
  defaults = {
    file_ignore_patterns = {
      '^dist/',
      '^node_modules/',
    },
  },
})

vim.keymap.set('n', '<leader>ff', function()
  builtins.find_files()
end)
vim.keymap.set('n', '<leader>fg', function()
  builtins.live_grep()
end)
vim.keymap.set('n', '<leader>fb', function()
  builtins.buffers()
end)
vim.keymap.set('n', '<leader>fh', function()
  builtins.help_tags()
end)
