return {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = { "zbirenbaum/copilot.lua" },

    -- load when you press any of these keys or use the :CopilotChat command
    cmd = "CopilotChat",
    keys = {
        -- open the chat split
        { "<leader>cc", "<cmd>CopilotChat<CR>", mode = "n", desc = "CopilotChat: Open chat" },
        { "<C-\\>",     "<cmd>CopilotChat<CR>", mode = "i", desc = "CopilotChat: Open chat" },

        -- your one-shot fix mappings
        {
            "<leader>cf",
            function() require("CopilotChat").ask("Fix this code") end,
            mode = "v",
            desc = "CopilotChat: Fix selection",
        },
        {
            "<leader>ce",
            function()
                vim.ui.input({ prompt = "Copilot prompt: " }, function(input)
                    if input and #input > 0 then
                        require("CopilotChat").ask(input)
                    end
                end)
            end,
            mode = "v",
            desc = "CopilotChat: Custom prompt for selection",
        },
    },

    opts = {
        debug = false,

        -- inside the chat buffer:
        mappings = {
            open   = { insert = "<C-\\>", normal = "<leader>cc" },
            close  = "<Esc>",
            submit = "<C-s>",
            -- (you can also remap scroll, next/prev, etc. here)
        },
    },
}
