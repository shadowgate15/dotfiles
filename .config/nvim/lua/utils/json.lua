local json = require("plenary.json")

local M = {}

-- Read a JSON file
---@generic T : table
---@param file string
--
---@return T
function M.read_json(file)
  local lines = vim.fn.readfile(file)
  local joined = vim.fn.join(lines)
  local stripped = json.json_strip_comments(joined, {})

  return vim.fn.json_decode(stripped)
end

return M
