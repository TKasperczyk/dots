return {
    'augmentcode/augment.vim',
    event = "VeryLazy",
    config = function()
        -- Disable default Tab mapping to avoid conflicts
        vim.g.augment_disable_tab_mapping = true

        -- Custom keymaps for Augment
        local keymap = vim.keymap.set

        -- Chat commands
        keymap("n", "<leader>ac", ":Augment chat<CR>", { desc = "Augment chat" })
        keymap("v", "<leader>ac", ":Augment chat<CR>", { desc = "Augment chat (visual)" })
        keymap("n", "<leader>an", ":Augment chat-new<CR>", { desc = "Augment new chat" })
        keymap("n", "<leader>at", ":Augment chat-toggle<CR>", { desc = "Augment toggle chat panel" })

        -- Enable/disable commands
        keymap("n", "<leader>ae", ":Augment enable<CR>", { desc = "Augment enable suggestions" })
        keymap("n", "<leader>ad", ":Augment disable<CR>", { desc = "Augment disable suggestions" })

        -- Accept suggestion with Ctrl+Y (alternative to Tab)
        keymap("i", "<C-y>", "<cmd>call augment#Accept()<cr>", { desc = "Accept Augment suggestion" })
    end
}
