-- noremap space
vim.keymap.set('n', '<space>', '<nop>')

-- close buffer
vim.keymap.set('n', '<leader>q', '<Cmd>q<CR>')

-- fast save
vim.keymap.set('n', '<leader>w', '<Cmd>up<CR>')

-- fast window switching
vim.keymap.set('n', '<leader><leader>', '<C-W>w')

-- fast escaping
vim.keymap.set('i', 'jj', '<ESC>', { remap = true })

-- ignore lines when going up and down
vim.keymap.set('n', 'j', 'gj')
vim.keymap.set('n', 'k', 'gk')

-- yank from current cursor position to end of the line
vim.keymap.set('n', 'Y', 'y$')

-- Continuous visual shifting (does not exit Visual mode)
vim.keymap.set('x', '>', '>gv')
vim.keymap.set('x', '<', '<gv')

-- reload config
vim.keymap.set('n', '<leader>sv', function()
  for name, _ in pairs(package.loaded) do
    if name:match('^core') then
      package.loaded[name] = nil
    end
  end

  dofile(vim.env.MYVIMRC)

  print('Nvim config successfully reloaded!')
end)
