local hop = require('hop')
local directions = require('hop.hint').HintDirection

hop.setup()

vim.keymap.set('', 'f', function()
  hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true })
end, { remap = true })

vim.keymap.set('', 'F', function()
  hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true })
end, { remap = true })

vim.keymap.set('', 's', function()
  hop.hint_patterns({})
end, { remap = true })

vim.keymap.set('', '<leader>j', function()
  hop.hint_lines({ direction = directions.AFTER_CURSOR })
end)

vim.keymap.set('', '<leader>k', function()
  hop.hint_lines({ direction = directions.BEFORE_CURSOR })
end)
