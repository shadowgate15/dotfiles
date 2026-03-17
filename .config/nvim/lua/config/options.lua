-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.relativenumber = false

vim.filetype.add({
  extension = {
    log = "log",
  },
})

vim.filetype.add({
  filename = {
    ["project.json"] = function(path, _bufnr)
      local nxFile = vim.fn.findfile("nx.json", ".")

      if nxFile ~= "" then
        return "jsonc"
      end

      return "json"
    end,
  },
})
