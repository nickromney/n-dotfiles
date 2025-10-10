-- Core Vim Options
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Line numbers
vim.opt.relativenumber = true
vim.opt.number = true

-- Tabs & indentation
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true

-- Line wrapping
vim.opt.wrap = false

-- Search settings
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Cursor line
vim.opt.cursorline = true

-- Appearance
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.signcolumn = "yes"

-- Backspace
vim.opt.backspace = "indent,eol,start"

-- Clipboard
vim.opt.clipboard:append("unnamedplus")

-- Split windows
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Swap files
vim.opt.swapfile = false

-- Scrolloff
vim.opt.scrolloff = 8
