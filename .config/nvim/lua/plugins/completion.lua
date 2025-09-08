return {
    "saghen/blink.cmp",
    dependencies = {
        "rafamadriz/friendly-snippets",
        "fang2hou/blink-copilot",
    },
    build = "cargo build --release",
    version = "v0.*",
    
    config = function(_, opts)
        -- Setup blink-copilot first
        require('blink-copilot').setup({})
        require('blink.cmp').setup(opts)
    end,

    opts = {
        keymap = { preset = "default" },

        appearance = {
            nerd_font_variant = "mono",
        },

        signature = { enabled = true },

        -- Copilot integration moved here
        sources = {
            default = { "lsp", "path", "snippets", "buffer", "copilot" },
            providers = {
                copilot = {
                    name = "copilot",
                    module = "blink-copilot",
                    score_offset = 100,
                    async = true,
                },
            },
        },
    },
}
