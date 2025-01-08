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
  {
    "folke/noice.nvim",
    opts = {
      routes = {
        {
          filter = {
            event = "lsp",
            kind = "progress",
            cond = function(message)
              local client = vim.tbl_get(message.opts, "progress", "client")
              return client == "vtsls"
            end,
          },
          opts = { timeout = 5000 },
        },
      },
    },
  },
}
