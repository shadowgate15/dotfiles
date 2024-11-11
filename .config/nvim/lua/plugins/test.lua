return {
  {
    "nvim-neotest/neotest",
    version = "5.2.4",
    pin = true,
    dependencies = { "nvim-neotest/neotest-jest" },
    opts = {
      adapters = {
        ["neotest-jest"] = {
          jestCommand = function()
            local nx_cmd = require("nx..neotest").jest_command()

            if nx_cmd then
              return nx_cmd
            end

            return "yarn test"
          end,
          jestConfigFile = function(file)
            local nx_config = require("nx.neotest").jest_config_file(file)

            if nx_config then
              return nx_config
            end

            -- Handle non-Nx workspaces
            if string.find(file, "/packages/") then
              return string.match(file, "(.-/[^/]+/)src") .. "jest.config.ts"
            end

            return vim.fn.getcwd() .. "/jest.config.ts"
          end,
          cwd = function(file)
            local nx_cwd = require("nx.neotest").get_cwd()

            if nx_cwd then
              return nx_cwd
            end

            if string.find(file, "/packages/") then
              return string.match(file, "(.-/[^/]+/)src")
            end

            return vim.fn.getcwd()
          end,
        },
      },
    },
    -- config = function(opts)
    --   require("nx").setup_neotest(vim.tbl_extend("force", opts, {
    --     adapters = {
    --       ["neotest-jest"] = {
    --         jestCommand = "yarn test",
    --         jestConfigFile = function(file)
    --           -- Handle non-Nx workspaces
    --           if string.find(file, "/packages/") then
    --             return string.match(file, "(.-/[^/]+/)src") .. "jest.config.ts"
    --           end
    --
    --           return vim.fn.getcwd() .. "/jest.config.ts"
    --         end,
    --         cwd = function(file)
    --           if string.find(file, "/packages/") then
    --             return string.match(file, "(.-/[^/]+/)src")
    --           end
    --
    --           return vim.fn.getcwd()
    --         end,
    --       },
    --     },
    --   }))
    --
    --   require("neotest").setup(opts)
    -- end,
  },
}
