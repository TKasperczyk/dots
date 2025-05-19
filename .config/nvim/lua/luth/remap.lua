-- Stop the yank
vim.keymap.set('n', 'd', '"_d', { noremap = true })
vim.keymap.set('v', 'd', '"_d', { noremap = true })

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

vim.keymap.set("n", "<leader>pv", function()
    -- Check if Neo-tree is already open on the left
    local is_open = vim.fn.bufwinnr("neo-tree") ~= -1
    if is_open then
        vim.cmd("Neotree close")
    else
        vim.cmd("Neotree reveal")
    end
end, { desc = "Toggle NeoTree at current file" })
