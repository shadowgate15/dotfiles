-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
vim.api.nvim_create_user_command("FormatDisable", function(args)
  if args.bang then
    -- FormatDisable! will disable formatting just for this buffer
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
end, {
  desc = "Disable autoformat-on-save",
  bang = true,
})

vim.api.nvim_create_user_command("FormatEnable", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end, {
  desc = "Re-enable autoformat-on-save",
})

vim.api.nvim_create_user_command("FormatJSON", function()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local formatted = vim.fn.systemlist({
    "python3",
    "-m",
    "json.tool",
    "--indent",
    "2",
  }, lines)

  if vim.v.shell_error ~= 0 then
    vim.notify("JSON formatting failed:\n" .. table.concat(formatted, "\n"), vim.log.levels.ERROR)
    return
  end

  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted)
  vim.fn.winrestview(view)
end, {
  desc = "Format JSON with Python using two-space indentation",
})
