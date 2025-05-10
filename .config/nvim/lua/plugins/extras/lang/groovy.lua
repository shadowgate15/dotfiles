return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "groovy-language-server",
        "npm-groovy-lint",
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "groovy" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        groovyls = {},
      },
    },
  },
  {
    "nvimtools/none-ls.nvim",
    optional = true,
    opts = function(_, opts)
      local nls = require("null-ls")
      local with = { disabled_filetypes = { "java" } }

      opts.sources = vim.list_extend(opts.sources or {}, {
        nls.builtins.formatting.npm_groovy_lint.with(with),
        nls.builtins.diagnostics.npm_groovy_lint.with(with),
      })
    end,
  },
}
