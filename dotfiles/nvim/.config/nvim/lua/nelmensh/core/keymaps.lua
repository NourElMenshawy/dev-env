--[[

=====================================================================
==================== KICKSTART PRESENTS          ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   NELMENSH .NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:keymap.lua    ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==neio==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================
--]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.keymap.set('', '<Space>', '<Nop>', { silent = true, noremap = true })
vim.keymap.set('n', 's', '<Nop>', { noremap = true, silent = true })
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local keymap = vim.keymap

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Window Management 
keymap.set('n', "<leader>s|", "<C-w>v", {desc = "Split window vertically"})
keymap.set('n', "<leader>s-", "<C-w>s", {desc = "Split window horizontally"})
keymap.set('n', "<leader>se", "<C-w>=", {desc = "Split window equally "})
keymap.set('n', "<leader>sk", "<cmd>close<CR>", {desc = "Close current split"})


-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })


--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<leader><left>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<leader><right>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<leader><down>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<leader><up>', '<C-w><C-k>', { desc = 'Move focus to the lower window' })
