return {
    "saghen/blink.cmp",
    dependencies = {
        "rafamadriz/friendly-snippets",
        "giuxtaposition/blink-cmp-copilot",
    },
    build = "cargo build --release",
    version = "v0.*",

    opts = {
        keymap = { preset = "default" },

        appearance = {
            -- keep using nvim-cmp as frontend, but include Copilot as a source
            use_nvim_cmp_as_default = true,
            nerd_font_variant       = "mono",
        },

        signature = { enabled = true },

        -- Copilot integration moved here
        sources = {
            default = { "lsp", "path", "snippets", "buffer", "copilot" },
            providers = {
                copilot = {
                    name         = "copilot",
                    module       = "blink-cmp-copilot",
                    score_offset = 100,
                    async        = true,
                },
            },
        },
    },
}
