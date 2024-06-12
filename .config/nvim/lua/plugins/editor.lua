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
      { "<leader>ot", "<cmd>OverseerToggle<cr>", { desc = "Toogle Overseer" } },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      defaults = {
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
      defaults = {
        ["<leader>w"] = { name = "+windows/workspaces" },
      },
    },
  },
}
