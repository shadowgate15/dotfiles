vim.opt.termguicolors = true

vim.opt.background = 'dark'

vim.cmd([[
try
  colorscheme carbonfox
catch
  echo "Failed to laod colorscheme."
endtry
]])

vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
