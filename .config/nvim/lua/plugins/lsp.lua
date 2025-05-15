return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "mason-org/mason.nvim",
            "mason-org/mason-lspconfig.nvim",
            "folke/lazydev.nvim",
            "saghen/blink.cmp",
            "folke/neodev.nvim"
        },
        config = function()
            require("neodev").setup()

            local capabilities = require("blink.cmp").get_lsp_capabilities()
            local util         = require("lspconfig.util")


            local lspconfig = require("lspconfig")
            local util      = require("lspconfig.util")
            local caps      = require("blink.cmp").get_lsp_capabilities()

            lspconfig.vtsls.setup({
                capabilities        = caps,
                init_options        = {
                    lint     = true,
                    unstable = true,
                    suggest  = {
                        imports = { hosts = { ["https://deno.land"] = true } }
                    },
                },
                root_dir            = util.root_pattern("tsconfig.json"),
                single_file_support = false,
            });
            lspconfig.denols.setup({
                capabilities        = caps,
                init_options        = {
                    lint     = true,
                    unstable = true,
                    suggest  = {
                        imports = { hosts = { ["https://deno.land"] = true } }
                    },
                },
                root_dir            = util.root_pattern("deno.json", "deno.jsonc"),
                single_file_support = false,
            })
            lspconfig.lua_ls.setup({
                capabilities        = caps,
                init_options        = {
                    lint     = true,
                    unstable = true,
                },
                single_file_support = true,
            })
            lspconfig.svelte.setup({
                capabilities        = caps,
                init_options        = {
                    lint     = true,
                    unstable = true,
                },
                root_dir            = util.root_pattern("svelte.config.json"),
                single_file_support = false,
            })
            lspconfig.tailwindcss.setup({
                capabilities        = caps,
                init_options        = {
                    lint     = true,
                    unstable = true,
                },
                root_dir            = util.root_pattern("tailwind.config.ts"),
                single_file_support = false,
            })

            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = { "lua_ls", "denols", "svelte", "vtsls" },
                automatic_enable = false,
            })

            --vim.lsp.enable("denols")
            vim.lsp.enable("svelte")
            vim.lsp.enable("vtsls")


            vim.api.nvim_create_autocmd('LspAttach', {
                callback = function(args)
                    local c = vim.lsp.get_client_by_id(args.data.client_id)
                    if not c then return end

                    -- Format the current buffer on save
                    vim.api.nvim_create_autocmd('BufWritePre', {
                        buffer = args.buf,
                        callback = function()
                            vim.lsp.buf.format({ bufnr = args.buf, id = c.id })
                        end,
                    })
                end,
            })
        end,
    },
}
