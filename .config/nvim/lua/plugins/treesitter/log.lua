return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)

      local parser_config = require("nvim-treesitter.parsers").get_parser_configs()

      ---@diagnostic disable-next-line: inject-field
      parser_config.log = {
        install_info = {
          url = "https://github.com/Tudyx/tree-sitter-log",
          files = { "src/parser.c" },
          branch = "main",
          generate_requires_npm = true,
          requires_generate_from_grammar = true,
        },
      }

      vim.treesitter.language.register("log", "log")
    end,
  },
}
