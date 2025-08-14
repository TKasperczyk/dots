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
                capabilities         = caps,
                autoUseWorkspaceTsdk = true,
                typescript           = {
                    tsdk = "./node_modules/typescript/lib",
                },
                init_options         = {
                    lint     = true,
                    unstable = true,
                    suggest  = {
                        imports = { hosts = { ["https://deno.land"] = true } }
                    },
                },
                filetypes            = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
                root_dir             = function(fname)
                    -- Don't activate for .svelte.ts files - let Svelte handle them
                    if fname:match("%.svelte%.ts$") then
                        return nil
                    end
                    -- Don't activate in Deno projects - let denols handle them exclusively
                    local deno_root = util.root_pattern("deno.json", "deno.jsonc")(fname)
                    if deno_root then
                        return nil
                    end
                    -- Only activate if we find TypeScript config files but no Deno config
                    local ts_root = util.root_pattern("tsconfig.json", "jsconfig.json")(fname)
                    if ts_root then
                        -- Double check no deno.json in the TypeScript project root
                        if vim.fn.filereadable(ts_root .. "/deno.json") == 1 or vim.fn.filereadable(ts_root .. "/deno.jsonc") == 1 then
                            return nil
                        end
                        return ts_root
                    end
                    -- Fall back to package.json for JavaScript projects without deno
                    local pkg_root = util.root_pattern("package.json")(fname)
                    if pkg_root then
                        if vim.fn.filereadable(pkg_root .. "/deno.json") == 1 or vim.fn.filereadable(pkg_root .. "/deno.jsonc") == 1 then
                            return nil
                        end
                        return pkg_root
                    end
                    return nil
                end,
                single_file_support  = false,
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
                root_dir            = function(fname)
                    -- Only activate if we find deno.json or deno.jsonc
                    return util.root_pattern("deno.json", "deno.jsonc")(fname)
                end,
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
                capabilities = caps,
                filetypes = {
                    "css",
                    "scss", 
                    "sass",
                    "html",
                    "javascript",
                    "javascriptreact", 
                    "typescript",
                    "typescriptreact",
                    "svelte",
                    "vue"
                },
                root_dir = util.root_pattern(
                    "tailwind.config.js",
                    "tailwind.config.cjs", 
                    "tailwind.config.mjs",
                    "tailwind.config.ts",
                    "svelte.config.js"
                ),
                settings = {
                    tailwindCSS = {
                        classAttributes = { "class", "className", "class:list", "classList", "ngClass" },
                        includeLanguages = {
                            svelte = "html"
                        }
                    }
                },
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

            lspconfig.basedpyright.setup({
                capabilities = caps,
                settings = {
                    basedpyright = {
                        analysis = {
                            typeCheckingMode = "basic",
                            autoSearchPaths = true,
                            useLibraryCodeForTypes = true,
                        },
                    },
                },
                root_dir = util.root_pattern("pyproject.toml", "setup.py", "requirements.txt", ".git"),
                single_file_support = true,
            })

            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = { "lua_ls", "denols", "svelte", "vtsls", "phpactor", "jsonls", "basedpyright", "tailwindcss" },
                automatic_enable = false,
            })

            vim.lsp.enable("denols")
            vim.lsp.enable("jsonls")
            vim.lsp.enable("svelte")
            vim.lsp.enable("vtsls")
            vim.lsp.enable("lua_ls")
            vim.lsp.enable("phpactor")
            vim.lsp.enable("basedpyright")
            vim.lsp.enable("tailwindcss")

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
                    local client = vim.lsp.get_client_by_id(event.data.client_id)

                    -- Stop vtsls if it attaches to a file in a Deno project
                    if client and client.name == "vtsls" then
                        local current_file = vim.api.nvim_buf_get_name(bufnr)
                        if util.root_pattern("deno.json", "deno.jsonc")(current_file) then
                            vim.lsp.stop_client(client.id)
                            return
                        end
                    end

                    -- Stop denols if it attaches to a file NOT in a Deno project
                    if client and client.name == "denols" then
                        local current_file = vim.api.nvim_buf_get_name(bufnr)
                        if not util.root_pattern("deno.json", "deno.jsonc")(current_file) then
                            vim.lsp.stop_client(client.id)
                            return
                        end
                    end

                    vim.keymap.set("n", "gd", smart_goto_definition,
                        { buffer = bufnr, desc = "Smart LSP Go to definition" })
                end,
            })




            vim.api.nvim_create_autocmd('BufWritePre', {
                pattern = "*",
                callback = function()
                    vim.lsp.buf.format({
                        filter = function(client)
                            -- For TypeScript/JavaScript files in Deno projects, use denols
                            if vim.bo.filetype == "typescript" or vim.bo.filetype == "javascript" then
                                local current_file = vim.api.nvim_buf_get_name(0)
                                if util.root_pattern("deno.json", "deno.jsonc")(current_file) then
                                    return client.name == "denols"
                                else
                                    return client.name == "vtsls"
                                end
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
