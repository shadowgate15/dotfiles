local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

print(lazypath)

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  -- bootstrap lazy.nvim
  -- stylua: ignore
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup(
  ---@type LazyConfig
  {
    spec = {
      -- add LazyVim and import its plugins
      { "LazyVim/LazyVim", import = "lazyvim.plugins" },
      -- import any extras modules here
      { import = "lazyvim.plugins.extras.coding.mini-surround" },
      { import = "lazyvim.plugins.extras.coding.yanky" },
      { import = "lazyvim.plugins.extras.editor.dial" },
      { import = "lazyvim.plugins.extras.editor.inc-rename" },
      { import = "lazyvim.plugins.extras.lsp.neoconf" },
      { import = "lazyvim.plugins.extras.lsp.none-ls" },
      { import = "lazyvim.plugins.extras.ui.mini-animate" },
      { import = "lazyvim.plugins.extras.ui.treesitter-context" },
      { import = "lazyvim.plugins.extras.util.dot" },
      { import = "lazyvim.plugins.extras.util.mini-hipatterns" },
      -- import/override with your plugins
      { import = "plugins" },
      { import = "plugins.extras.util" },
      { import = "plugins.extras.lang" },
      { import = "plugins.project.root" },
    },
    defaults = {
      -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
      -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
      lazy = false,
      -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
      -- have outdated releases, which may break your Neovim install.
      version = false, -- always use the latest git commit
      -- version = "*", -- try installing the latest stable version for plugins that support semver
    },
    install = { colorscheme = { "tokyonight", "habamax" } },
    checker = { enabled = true }, -- automatically check for plugin updates
    performance = {
      rtp = {
        -- disable some rtp plugins
        disabled_plugins = {
          -- "gzip",
          -- "matchit",
          -- "matchparen",
          -- "netrwPlugin",
          -- "tarPlugin",
          "tohtml",
          "tutor",
          -- "zipPlugin",
        },
      },
    },
    dev = {
      path = "~/Documents/projects",
      patterns = {
        -- "shadowgate15/nx.nvim"
      },
    },
  }
)
