return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "mason-org/mason.nvim",
            "mason-org/mason-lspconfig.nvim",
            "folke/lazydev.nvim",
            "saghen/blink.cmp",
            "folke/neodev.nvim",
            "b0o/SchemaStore.nvim",
        },
        config = function()
            require("neodev").setup()

            local lspconfig = require("lspconfig")
            local util      = require("lspconfig.util")
            local caps      = require("blink.cmp").get_lsp_capabilities()

            lspconfig.jsonls.setup({
                capabilities = caps,
                settings = {
                    json = {
                        schemas = require('schemastore').json.schemas(),
                        validate = { enable = true },
                    },
                },
                init_options = {
                    provideFormatter = true,
                },
                single_file_support = true,
            })

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

            local svelte_caps = vim.tbl_deep_extend("force", caps, {
                workspace = { didChangeWatchedFiles = false }
            })

            local function svelte_on_attach(client)
                if client.name == "svelte" then
                    client.server_capabilities.documentFormattingProvider = true
                    client.server_capabilities.documentRangeFormattingProvider = true
                    vim.api.nvim_create_autocmd("BufWritePost", {
                        pattern = { "*.js", "*.ts" },
                        group = vim.api.nvim_create_augroup("svelte_ondidchangetsorjsfile", { clear = true }),
                        callback = function(ctx)
                            client.notify("$/onDidChangeTsOrJsFile", { uri = ctx.match })
                        end,
                    })
                end
            end

            lspconfig.svelte.setup({
                capabilities = svelte_caps,
                on_attach = svelte_on_attach,
                init_options = {
                    lint     = true,
                    unstable = true,
                },
                filetypes = { "svelte", "typescript", "javascript" },
                root_dir = util.root_pattern("svelte.config.js"),
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
            lspconfig.phpactor.setup({
                capabilities = caps,
                init_options = {
                    ["language_server_phpstan.enabled"]      = false,
                    ["language_server_psalm.enabled"]        = false,
                    ["language_server_php_cs_fixer.enabled"] = false,
                },
                -- detect the project root by composer.json or git:
                root_dir = util.root_pattern("composer.json", ".git"),
            })

            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = { "lua_ls", "denols", "svelte", "vtsls", "phpactor", "jsonls" },
                automatic_enable = false,
            })

            --vim.lsp.enable("denols")
            vim.lsp.enable("jsonls")
            vim.lsp.enable("svelte")
            vim.lsp.enable("vtsls")
            vim.lsp.enable("lua_ls")
            vim.lsp.enable("phpactor")

            vim.api.nvim_create_autocmd('BufWritePre', {
                pattern = "*",
                callback = function()
                    vim.lsp.buf.format({
                        filter = function(client)
                            -- For TypeScript/JavaScript files, only use vtsls
                            if vim.bo.filetype == "typescript" or vim.bo.filetype == "javascript" then
                                return client.name == "vtsls"
                            end
                            -- For Svelte files, only use svelte
                            if vim.bo.filetype == "svelte" then
                                return client.name == "svelte"
                            end
                            -- For JSON files, use jsonls
                            if vim.bo.filetype == "json" then
                                return client.name == "jsonls"
                            end
                            -- For other files, use any client that supports formatting
                            return client.supports_method("textDocument/formatting")
                        end,
                        timeout_ms = 2000,
                    })
                end,
            })
        end,
    },
}
