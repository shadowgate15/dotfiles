return {
  -- Task manager
  -- https://github.com/stevearc/overseer.nvim
  {
    "stevearc/overseer.nvim",
    opts = {
      templates = { "core" },
    },
    keys = {
      { "<leader>or", "<cmd>OverseerRun<cr>", { desc = "Run Overseer" } },
      { "<leader>oc", "<cmd>OverseerRunCmd<cr>", { desc = "Run Overseer CMD" } },
      { "<leader>ot", "<cmd>OverseerToggle<cr>", { desc = "Toogle Overseer" } },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        ["<leader>o"] = { name = "+overseer" },
      },
    },
  },
  -- Workspaces
  -- https://github.com/natecraddock/workspaces.nvim
  {
    "natecraddock/workspaces.nvim",
    opts = {},
    config = function(opts)
      require("workspaces").setup(opts)

      LazyVim.on_load("telescope.nvim", function()
        require("telescope").load_extension("workspaces")
      end)
    end,
    keys = {
      { "<leader>wf", "<cmd>Telescope workspaces<cr>", desc = "Find workspace" },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        ["<leader>w"] = { name = "+windows/workspaces" },
      },
    },
  },
  {
    "folke/flash.nvim",
    keys = {
      {
        "<leader>k",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump({
            search = { forward = false, wrap = false, mutli_window = false, mode = "search", max_length = 0 },
            label = { after = { 0, 0 } },
            pattern = "^",
          })
        end,
        { desc = "Flash Up Lines" },
      },
      {
        "<leader>j",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump({
            search = { forward = true, wrap = false, mutli_window = false, mode = "search", max_length = 0 },
            label = { after = { 0, 0 } },
            pattern = "^",
          })
        end,
        { desc = "Flash Down Lines" },
      },
    },
  },
}
