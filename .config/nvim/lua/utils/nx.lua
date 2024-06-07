local Path = require("plenary.path")
local json = require("utils.json")

local M = {}

-- Get the root of the NX project
--
---@param file string
--
---@return string?
local function get_project_file(file)
  local path = Path:new(file)

  while path:parent() do
    local projectJson = Path:new(path, "project.json")

    if projectJson:exists() then
      return projectJson:absolute()
    end

    path = path:parent()
  end
end

-- Determine if CWD is an NX workspace
--
---@return boolean
M.is_workspace = function()
  local nxJson = Path:new(vim.fn.getcwd(), "nx.json")

  return nxJson:exists()
end

-- Get project info
--
---@param file string
--
---@return table?
M.get_project_info = function(file)
  -- If not an NX workspace, return
  if not M.isWorkspace() then
    return
  end

  local projectJsonPath = get_project_file(file)

  -- If no project.json file found, return
  if not projectJsonPath then
    return
  end

  return json.read_json(projectJsonPath)
end

-- Get jest config path
--
---@param file string
--
---@return string?
M.get_jest_config = function(file)
  local projectInfo = M.get_project_info(file)

  if not projectInfo then
    return
  end

  local jestConfig = projectInfo.targets.test.options.jestConfig

  if jestConfig then
    return Path:new(vim.fn.getcwd(), jestConfig):absolute()
  end
end

return M
