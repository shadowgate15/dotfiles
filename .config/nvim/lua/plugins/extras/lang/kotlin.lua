local function enabled()
  return LazyVim.has_extra("lang.kotlin")
end

return {
  ---@type LazyPlugin
  {
    "neovim/nvim-lspconfig",
    enabled = enabled,
    opts = {
      servers = {
        kotlin_language_server = {
          cmd = {
            vim.fn.stdpath("data")
              .. "/lazy/kotlin-language-server/server/build/install/server/bin/kotlin-language-server",
          },
        },
      },
    },
  },
  ---@type LazyPlugin
  {
    "kotlin-community-tools/kotlin-language-server",
    lazy = true,
    ft = { "kotlin" },
    enabled = enabled,
    build = "./gradlew :server:installDist",
  },
}
