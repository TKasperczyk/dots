return {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = { "zbirenbaum/copilot.lua" },
    opts = { debug = false },
    keys = {
        {
            "<leader>cf",
            function()
                require("CopilotChat").ask("Fix this code")
            end,
            mode = { "v" },
            desc = "Copilot: Fix selection",
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
            mode = { "v" },
            desc = "Copilot: Custom prompt for selection",
        },
    },
}
