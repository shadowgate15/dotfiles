-- This is a map of paths to their corresponding project specifications.
local pathMap = require("plugins.project.path-map")

local cwd = LazyVim.root.cwd()

if vim.tbl_contains(pathMap, cwd) then
  return require(pathMap[cwd])
end

return {}
