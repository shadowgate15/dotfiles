return {
  -- Task manager
  -- https://github.com/stevearc/overseer.nvim
  {
    "stevearc/overseer.nvim",
    opts = {
      templates = { "core" },
    },
    keys = {
      { "<leader>r", "<cmd>OverseerRun<cr>" },
      { "<leader>rt", "<cmd>OverseerToggle<cr>" },
    },
  },
}
