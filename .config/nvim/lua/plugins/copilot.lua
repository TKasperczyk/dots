return {
    "zbirenbaum/copilot.lua",
    opts = {
        suggestion = { enabled = false },
        panel = { enabled = false },
    },
    cmd = "Copilot",
    event = "VimEnter", -- Changed from InsertEnter to VimEnter for earlier attachment
    config = function(_, opts)
        require("copilot").setup(opts)
        -- Auto-attach to all file buffers
        vim.api.nvim_create_autocmd("BufEnter", {
            pattern = "*",
            callback = function()
                if vim.bo.filetype ~= "" and vim.bo.buftype == "" then
                    vim.schedule(function()
                        local copilot_ok, copilot = pcall(require, "copilot.client")
                        if copilot_ok then
                            copilot.buf_attach()
                        end
                    end)
                end
            end,
        })
    end,
}
