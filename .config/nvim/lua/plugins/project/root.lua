local function try_get_path_map()
  local ok, val = pcall(require, "plugins.project.path-map")

  if ok then
    return val
  end

  return {}
end

local cwd = LazyVim.root.cwd()
local pathMap = try_get_path_map()

if pathMap[cwd] then
  return require("plugins.project." .. pathMap[cwd])
end

return {}
