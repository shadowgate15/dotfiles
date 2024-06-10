return {
  {
    "nvim-neotest/neotest",
    version = "5.2.4",
    pin = true,
    dependencies = { "nvim-neotest/neotest-jest" },
    opts = {
      adapters = {
        -- ["nx.neotest"] = {},
        ["neotest-jest"] = {
          jestCommand = "yarn test",
          jestConfigFile = function(file)
            -- Handle non-Nx workspaces
            if string.find(file, "/packages/") then
              return string.match(file, "(.-/[^/]+/)src") .. "jest.config.ts"
            end

            return vim.fn.getcwd() .. "/jest.config.ts"
          end,
          cwd = function(file)
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
