return {
  {
    "shadowgate15/nx.nvim",
    dependencies = {
      "stevearc/overseer.nvim",
    },
    -- name = "nx",
    opts = {},
  },
  -- https://github.com/LintaoAmons/scratch.nvim
  {
    "LintaoAmons/scratch.nvim",
    event = "VeryLazy",
    dependencies = {
      "ibhagwan/fzf-lua",
    },
  },
}
