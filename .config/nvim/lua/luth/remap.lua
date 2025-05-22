-- Stop the yank
vim.keymap.set('n', 'd', '"_d', { noremap = true })
vim.keymap.set('v', 'd', '"_d', { noremap = true })

vim.keymap.set('n', 'c', '"_c', { noremap = true })
vim.keymap.set('v', 'c', '"_c', { noremap = true })

vim.keymap.set('n', 'x', '"_x', { noremap = true })
vim.keymap.set('v', 'x', '"_x', { noremap = true })

vim.keymap.set('n', 's', '"_s', { noremap = true })
vim.keymap.set('v', 's', '"_s', { noremap = true })

-- Uppercase variants
vim.keymap.set('n', 'C', '"_C', { noremap = true })
vim.keymap.set('n', 'D', '"_D', { noremap = true })
vim.keymap.set('n', 'S', '"_S', { noremap = true })

-- Optional: X (backspace-like delete in normal mode)
vim.keymap.set('n', 'X', '"_X', { noremap = true })

-- Cut (delete and yank) using d as it was before
vim.keymap.set('v', '<leader>d', 'd', { noremap = true })
vim.keymap.set('n', '<leader>d', 'd', { noremap = true })

-- Go to next diagnostic
vim.keymap.set("n", "]d", function()
    vim.diagnostic.jump({ count = 1 })
end, { desc = "Next diagnostic" })

vim.keymap.set("n", "[d", function()
    vim.diagnostic.jump({ count = -1 })
end, { desc = "Previous diagnostic" })

-- Show all diagnostics in a location list
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist)

-- Show hover info (docs, etc.)
vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "LSP Hover" })

-- Go to definition
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "LSP Go to definition" })

vim.keymap.set("v", "<C-Down>", ":m '>+1'<CR>gv=gv")
vim.keymap.set("v", "<C-Up>", ":m '>-2'<CR>gv=gv")
