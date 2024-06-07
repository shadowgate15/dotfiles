local json = require("plenary.json")

local M = {}

-- Read a JSON file
--
---@param file string
--
---@return table?
M.read_json = function(file)
  local lines = vim.fn.readfile(file)
  local joined = vim.fn.join(lines)
  local stripped = json.json_strip_comments(joined, {})

  return vim.fn.json_decode(stripped)
end

return M
