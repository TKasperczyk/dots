vim.opt.exrc             = true -- Enable reading local config files
vim.opt.secure           = true -- Only run safe commands from local config

vim.g.mapleader          = " "
vim.g.maplocalleader     = "\\"

vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

require("luth.lazy")
require("luth.set")
require("luth.remap")
