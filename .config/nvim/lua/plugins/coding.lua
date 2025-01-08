return {
  {
    "saghen/blink.cmp",
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = {
        preset = "enter",
        ["<Tab>"] = {
          "select_next",
          "fallback",
        },
        ["<S-Tab>"] = { "select_prev", "fallback" },
      },
      completion = {
        list = {
          selection = {
            auto_insert = true,
          },
        },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      setup = {
        rust_analyzer = function()
          return true
        end,
      },
    },
  },
}
