return {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "gradle-language-server",
      },
    },
    {
      "neovim/nvim-lspconfig",
      opts = {
        servers = {
          gradle_ls = {},
        },
      },
    },
  },
}
