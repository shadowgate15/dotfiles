local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd([[packadd packer.nvim]])
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

require('packer').startup(function(use)
  -- https://github.com/wbthomason/packer.nvim
  use('wbthomason/packer.nvim')

  -- https://github.com/EdenEast/nightfox.nvim
  use('EdenEast/nightfox.nvim')

  -- https://github.com/mhartington/formatter.nvim
  use('mhartington/formatter.nvim')

  -- https://github.com/nvim-treesitter/nvim-treesitter
  use({
    'nvim-treesitter/nvim-treesitter',
    requires = {
      'JoosepAlviste/nvim-ts-context-commentstring',
    },
    run = function()
      require('nvim-treesitter.install').update({ with_sync = true })()
    end,
  })

  -- https://github.com/nvim-tree/nvim-tree.lua
  use({
    'nvim-tree/nvim-tree.lua',
    requires = {
      'nvim-tree/nvim-web-devicons', -- optional
    },
  })

  -- https://github.com/akinsho/bufferline.nvim
  use({ 'akinsho/bufferline.nvim', tag = '*', requires = { 'nvim-tree/nvim-web-devicons' } })

  -- https://github.com/nvim-telescope/telescope.nvim
  use({
    'nvim-telescope/telescope.nvim',
    tag = '0.1.x',
    requires = { 'nvim-lua/plenary.nvim' },
  })

  -- https://github.com/phaazon/hop.nvim
  use('phaazon/hop.nvim')

  -- https://github.com/NeogitOrg/neogit
  use({
    'NeogitOrg/neogit',
    requires = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'sindrets/diffview.nvim',
    },
  })

  -- https://github.com/numToStr/Comment.nvim
  use('numToStr/Comment.nvim')

  -- https://github.com/nvim-lualine/lualine.nvim
  use({
    'nvim-lualine/lualine.nvim',
    requires = { 'nvim-tree/nvim-web-devicons' },
  })

  -- https://github.com/windwp/nvim-autopairs
  use('windwp/nvim-autopairs')

  -- lsp setup
  -- https://github.com/williamboman/mason.nvim
  use({
    'williamboman/mason.nvim',
    requires = {
      -- https://github.com/williamboman/mason-lspconfig.nvim
      'williamboman/mason-lspconfig.nvim',
      -- https://github.com/neovim/nvim-lspconfig
      'neovim/nvim-lspconfig',
    },
  })

  -- cmp setup
  -- https://github.com/hrsh7th/nvim-cmp
  use({
    'hrsh7th/nvim-cmp',
    requires = {
      -- https://github.com/hrsh7th/cmp-nvim-lsp
      'hrsh7th/cmp-nvim-lsp',
      -- https://github.com/hrsh7th/cmp-buffer
      'hrsh7th/cmp-buffer',
      -- https://github.com/hrsh7th/cmp-path
      'hrsh7th/cmp-path',
      -- https://github.com/hrsh7th/cmp-cmdline
      'hrsh7th/cmp-cmdline',
      -- https://github.com/petertriho/cmp-git
      'petertriho/cmp-git',
      -- https://github.com/zbirenbaum/copilot-cmp
      'zbirenbaum/copilot-cmp',
      -- https://github.com/zbirenbaum/copilot.lua
      'zbirenbaum/copilot.lua',
      -- https://github.com/b0o/SchemaStore.nvim
      'b0o/schemastore.nvim',
      -- https://github.com/hrsh7th/cmp-vsnip
      'hrsh7th/cmp-vsnip',
      -- https://github.com/hrsh7th/vim-vsnip
      'hrsh7th/vim-vsnip',
      -- https://github.com/onsails/lspkind.nvim
      'onsails/lspkind.nvim',
    },
  })

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if packer_bootstrap then
    require('packer').sync()
  end
end)

local this_script_path = debug.getinfo(1).source:match('@?(.*/)')
local this_script_dir = vim.fn.fnamemodify(this_script_path, ':p:h')
local this_script_dir_script_paths = vim.fn.split(vim.fn.glob(this_script_dir .. '/*.lua'), '\n')

for _, script_path in ipairs(this_script_dir_script_paths) do
  local script_name = vim.fn.fnamemodify(script_path, ':t:r')
  if script_name ~= 'init' then
    require('core.plugins.' .. script_name)
  end
end
