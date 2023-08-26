-- change fillchars for folding, vertical split, end of buffer, and message separator
-- vim.o.fillchars = fold:\ ,vert:\│,eob:\ ,msgsep:‾

-- split window below/right when creating horizontal/vertical windows
vim.opt.splitbelow = true
vim.opt.splitright = true

vim.opt.timeoutlen = 1000

vim.opt.updatetime = 1000

vim.opt.swapfile = true

vim.opt.number = true

vim.opt.ignorecase = vim.opt.smartcase:get()

vim.opt.fileencoding = 'utf-8'
vim.opt.fileencodings = { 'ucs-bom', 'utf-8', 'cp936', 'gb18030', 'big5', 'euc-jp', 'euc-kr', 'latin1' }

-- break line at predefined characters
vim.opt.linebreak = true
-- character to show before the lines that have been soft-wrapped
vim.opt.showbreak = '↪'

-- list all matches and complete till longest common string
vim.opt.wildmode = 'list:longest'

-- minimum lines to keep above and below cursor when scrolling
vim.opt.scrolloff = 3

-- use mouse to select and resize windows, etc.
vim.opt.mouse = 'a' -- Enable mouse in several mode
vim.opt.mousemodel = 'popup' -- Set the behaviour of mouse

-- Do not show mode on command line since vim-airline can show it
vim.opt.showmode = false

vim.opt.fileformats = { 'unix', 'dos' } -- Fileformats to use for new files

vim.opt.inccommand = 'nosplit' -- Show the result of substitution in real time for preview

-- Auto-write the file based on some condition
vim.opt.autowrite = true

-- Persistent undo even after you close a file and re-open it
vim.opt.undofile = true

-- Do not show "match xx of xx" and other messages during auto-completion
vim.opt.shortmess:append('c')

vim.opt.spelllang = { 'en' } -- Spell languages

-- Align indent to next multiple value of shiftwidth. For its meaning,
-- see http://vim.1045645.n5.nabble.com/shiftround-option-td5712100.html
vim.opt.shiftround = true

vim.opt.virtualedit = 'block' -- Virtual edit is useful for visual block edit

-- Tilde (~) is an operator, thus must be followed by motions like `e` or `w`.
vim.opt.tildeop = true

-- Do not add two spaces after a period when joining lines or formatting texts,
-- see https://stackoverflow.com/q/4760428/6064933
vim.opt.joinspaces = false

vim.opt.synmaxcol = 200 -- Text after this column number is not highlighted
vim.opt.startofline = false

vim.opt.signcolumn = 'auto:3'

-- set fold method
vim.opt.foldenable = true
vim.opt.foldmethod = 'indent'
vim.opt.foldlevel = 99
