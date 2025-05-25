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
                filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
                root_dir            = function(fname)
                    -- Don't activate for .svelte.ts files - let Svelte handle them
                    if fname:match("%.svelte%.ts$") then
                        return nil
                    end
                    return util.root_pattern("tsconfig.json", "svelte.config.js")(fname)
                end,
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

            local function svelte_on_attach(client, bufnr)
                if client.name == "svelte" then
                    client.server_capabilities.documentFormattingProvider = true
                    client.server_capabilities.documentRangeFormattingProvider = true
                    
                    -- Enhanced workspace symbol support
                    client.server_capabilities.workspaceSymbolProvider = true
                    client.server_capabilities.definitionProvider = true
                    
                    vim.api.nvim_create_autocmd("BufWritePost", {
                        pattern = { "*.js", "*.ts", "*.svelte" },
                        group = vim.api.nvim_create_augroup("svelte_ondidchangetsorjsfile", { clear = true }),
                        callback = function(ctx)
                            client.notify("$/onDidChangeTsOrJsFile", { uri = ctx.file })
                        end,
                    })
                end
            end

            lspconfig.svelte.setup({
                capabilities = svelte_caps,
                on_attach = svelte_on_attach,
                init_options = {
                    configuration = {
                        svelte = {
                            plugin = {
                                typescript = {
                                    enabled = true,
                                    diagnostics = { enable = true },
                                    hover = { enable = true },
                                    completions = { enable = true },
                                    definitions = { enable = true },
                                    codeActions = { enable = true },
                                    selectionRange = { enable = true },
                                    rename = { enable = true },
                                },
                            },
                        },
                    },
                },
                settings = {
                    svelte = {
                        plugin = {
                            typescript = {
                                enabled = true,
                                diagnostics = { enable = true },
                                hover = { enable = true },
                                completions = { enable = true },
                                definitions = { enable = true },
                                codeActions = { enable = true },
                                selectionRange = { enable = true },
                                rename = { enable = true },
                            },
                        },
                    },
                },
                filetypes = { "svelte" },
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

            -- Custom go-to-definition that finds actual Svelte components
            local function smart_goto_definition()
                local word = vim.fn.expand('<cword>')
                local filename = vim.fn.expand('%:t')
                local is_svelte_project = vim.fn.findfile("svelte.config.js", ".;") ~= ""
                
                if is_svelte_project and filename:match("%.svelte%.ts$") then
                    -- Get all import lines from the current buffer
                    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                    
                    for _, line in ipairs(lines) do
                        -- Look for import statements that import the component under cursor
                        local pattern = "import%s+" .. word .. "%s+from%s+[\"']([^\"']+%.svelte)[\"']"
                        local svelte_path = line:match(pattern)
                        
                        if svelte_path then
                            -- Resolve the path relative to current file or using path aliases
                            local current_dir = vim.fn.expand('%:p:h')
                            local target_file
                            
                            if svelte_path:match("^@") then
                                -- Handle path aliases like @common
                                local root = vim.fn.finddir(".git/..", ".;")
                                if root == "" then root = "." end
                                
                                local cmd = string.format("find %s -path '*%s' -type f 2>/dev/null | head -1", 
                                    root, svelte_path:gsub("@[^/]+/", ""))
                                local handle = io.popen(cmd)
                                if handle then
                                    local result = handle:read("*a")
                                    handle:close()
                                    if result and result:match("%S") then
                                        target_file = result:match("^%s*(.-)%s*$")
                                    end
                                end
                            else
                                -- Relative path
                                target_file = vim.fn.resolve(current_dir .. "/" .. svelte_path)
                            end
                            
                            if target_file and vim.fn.filereadable(target_file) == 1 then
                                vim.cmd("edit " .. target_file)
                                return
                            end
                        end
                    end
                end
                
                vim.lsp.buf.definition()
            end

            -- Override gd in remap.lua by creating an autocommand
            vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(event)
                    local bufnr = event.buf
                    vim.keymap.set("n", "gd", smart_goto_definition, { buffer = bufnr, desc = "Smart LSP Go to definition" })
                end,
            })




            vim.api.nvim_create_autocmd('BufWritePre', {
                pattern = "*",
                callback = function()
                    vim.lsp.buf.format({
                        filter = function(client)
                            -- For TypeScript/JavaScript files, use vtsls
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
