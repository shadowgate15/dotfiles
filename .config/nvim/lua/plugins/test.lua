local nx = require("utils.nx")

return {
  {
    "nvim-neotest/neotest",
    version = "5.2.4",
    pin = true,
    dependencies = { "nvim-neotest/neotest-jest" },
    opts = {
      adapters = {
        ["neotest-jest"] = {
          jestCommand = "yarn test",
          jestConfigFile = function(file)
            -- Handle Nx workspaces
            local nxConfigFile = nx.get_jest_config(file)

            if nxConfigFile then
              return nxConfigFile
            end

            -- Handle non-Nx workspaces
            if string.find(file, "/packages/") then
              return string.match(file, "(.-/[^/]+/)src") .. "jest.config.ts"
            end

            return vim.fn.getcwd() .. "/jest.config.ts"
          end,
          cwd = function(file)
            if nx.is_workspace() then
              return vim.fn.getcwd()
            end

            if string.find(file, "/packages/") then
              return string.match(file, "(.-/[^/]+/)src")
            end

            return vim.fn.getcwd()
          end,
        },
      },
    },
  },
}
