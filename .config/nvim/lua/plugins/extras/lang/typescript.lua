-- https://github.com/yioneko/vtsls/issues/177#issuecomment-2191655359
return {
  ---@type LazyPlugin
  {
    "neovim/nvim-lspconfig",
    enabled = function()
      if LazyVim == nil then
        return false
      end

      return LazyVim.has_extra("lang.typescript")
    end,
    opts = {
      servers = {
        vtsls = {
          init_options = { hostInfo = "neovim" },
        },
      },
    },
  },
}
