return {
  -- Task manager
  -- https://github.com/stevearc/overseer.nvim
  {
    "stevearc/overseer.nvim",
    opts = {
      templates = { "core" },
    },
    keys = {
      { "<leader>or", "<cmd>OverseerRun<cr>" },
      { "<leader>ot", "<cmd>OverseerToggle<cr>" },
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
}
