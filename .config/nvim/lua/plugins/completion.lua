return {
    "saghen/blink.cmp",
    dependencies = {
        "rafamadriz/friendly-snippets",
    },
    build = "cargo build --release",
    version = "v0.*",

    opts = {
        keymap = { preset = "default" },

        appearance = {
            nerd_font_variant = "mono",
        },

        signature = { enabled = true },

        sources = {
            default = { "lsp", "path", "snippets", "buffer" },
        },
    },
}
