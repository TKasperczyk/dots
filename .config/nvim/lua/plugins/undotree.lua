return {
    'mbbill/undotree',
    config = function()
        vim.keymap.set("n", "<leader>uh", vim.cmd.UndotreeToggle)
    end
}
