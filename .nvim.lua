-- Dev shim.
--
-- When editing this plugin, Neovim's `exrc` sources this file automatically.
-- It puts this repository on the runtimepath and sets the plugin up, so the
-- `<leader>ac` mapping and `:AIContext` command work straight from a checkout.
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h")
vim.opt.runtimepath:prepend(root)
require("nvim-ai").setup()
