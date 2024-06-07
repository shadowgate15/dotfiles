local builtin = require("overseer.template.builtin")
local yarn = require("overseer.template.core.yarn")

local templates = {
  "yarn",
}

local M = {}

-- add custom templates
for _, template in pairs(templates) do
  table.insert(M, "core." .. template)
end

-- add builtin templates
for _, template in pairs(builtin) do
  if template == "npm" then
    --- Don't add npm if in yarn workspace is present
    if not yarn.check_for_workspaces() then
      table.insert(M, template)
    end
  else
    table.insert(M, template)
  end
end

return M
