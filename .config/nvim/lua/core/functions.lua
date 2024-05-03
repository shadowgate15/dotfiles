vim.api.nvim_create_user_command('AddToDictionary', function()
  vim.cmd([[ execute "normal! \<ESC>" ]])
  vim.fn.visualmode()

  local text = require('utils').get_visual_selection()

  for line in io.lines(vim.fn.environ().HOME .. '/.config/cspell/dictionary.txt') do
    if line == text then
      print('Word "' .. text .. '" already in dictionary!')

      return
    end
  end

  local file = assert(io.open(vim.fn.environ().HOME .. '/.config/cspell/dictionary.txt', 'a'))

  file:write(text .. '\n')

  file:close()
end, { range = true })

vim.api.nvim_create_user_command('Copy', function()
  vim.cmd([[ execute "normal! \<ESC>" ]])
  vim.fn.visualmode()

  local text = require('utils').get_visual_selection()

  vim.api.nvim_command(':!echo "' .. text .. '" | pbcopy')
end, { range = true })
