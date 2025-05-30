return {
  {
    "shadowgate15/nx.nvim",
    dependencies = {
      "stevearc/overseer.nvim",
    },
    -- name = "nx",
    opts = {},
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
          opts = {
            -- 1 minute timeout
            timeout = 1 * 60 * 1000,
          },
        },
      },
    },
  },
}
