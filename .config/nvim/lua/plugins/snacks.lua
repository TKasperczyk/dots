return {
    "folke/snacks.nvim",
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    priority = 1000,
    lazy = false,
    keys = {
        { "<leader>ps", function() Snacks.picker.grep() end,        desc = "Grep" },
        { "<leader>pf", function() Snacks.picker.files() end,       desc = "Smart Find Files" },
        { "<leader>pv", function() Snacks.explorer() end,           desc = "File Explorer" },
        { "<leader>gg", function() Snacks.lazygit() end,            desc = "Lazygit" },
        { "<leader>sd", function() Snacks.picker.diagnostics() end, desc = "Diagnostics" },
    },
    init = function()
        vim.api.nvim_create_autocmd("User", {
            pattern = "VeryLazy",
            callback = function()
                local snacks = require("snacks")
                -- Setup some globals for debugging (lazy-loaded)
                _G.dd = function(...)
                    snacks.debug.inspect(...)
                end
                _G.bt = function()
                    snacks.debug.backtrace()
                end
                vim.print = _G.dd -- Override print to use snacks for `:=` command

                -- Create some toggle mappings
                snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
                snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
                snacks.toggle.dim():map("<leader>uD")
            end,
        })
    end,
    config = function()
        local Path = require("plenary.path")
        local Snacks = require("snacks")

        -- Helpers from your Neo-Tree config:
        local function get_project_root()
            local lines = vim.fn.systemlist("git rev-parse --show-toplevel")
            if lines[1] and lines[1] ~= "" then return lines[1] end
            return vim.loop.cwd()
        end

        local function collect_files(path)
            local stat = vim.loop.fs_stat(path)
            if not stat then return {} end
            if stat.type == "file" then
                return { path }
            end
            local out = {}
            for _, name in ipairs(vim.fn.readdir(path) or {}) do
                if name ~= "." and name ~= ".." then
                    local child = Path:new(path) / name
                    for _, f in ipairs(collect_files(child:absolute())) do
                        table.insert(out, f)
                    end
                end
            end
            return out
        end

        local function get_final_extension(fn)
            local dot = fn:match("^.*()%.%w+$")
            if dot and dot > 1 and dot < #fn then
                return fn:sub(dot + 1)
            end
            return ""
        end

        local function filter_by_extension(files, allowed)
            if not allowed or #allowed == 0 then return files end
            local map = {}
            for _, ext in ipairs(allowed) do map[ext:lower()] = true end
            local res = {}
            for _, f in ipairs(files) do
                local ext = get_final_extension(Path:new(f).filename):lower()
                if ext == "" and map["no_extension"] or map[ext] then
                    table.insert(res, f)
                end
            end
            return res
        end

        local function build_markdown_with_extension_hint(files, root)
            local root_p = Path:new(root):absolute()
            local parts = {}
            for _, abs in ipairs(files) do
                local rel = Path:new(abs):make_relative(root_p)
                local ext = get_final_extension(Path:new(abs).filename):lower()
                if ext == "" then ext = "text" end
                local content = ""
                local fd = io.open(abs, "rb")
                if fd then
                    content = fd:read("*a")
                    fd:close()
                    if content:find("\0") then
                        content = "[binary content omitted]"
                    end
                else
                    content = "[could not read file]"
                end
                table.insert(parts, ("# %s\n```%s\n%s\n```\n"):format(rel, ext, content))
            end
            return table.concat(parts, "\n")
        end

        -- Single action that handles both single-cursor and multi-selection:
        local function copy_for_llm_action(picker, item)
            -- gather file paths from either selected or current
            local picks = #picker:selected() > 0 and picker:selected() or { item }
            local all = {}
            local seen = {}
            for _, it in ipairs(picks) do
                for _, f in ipairs(collect_files(it.file)) do
                    if not seen[f] then
                        all[#all + 1] = f
                        seen[f] = true
                    end
                end
            end

            -- filter extensions
            local allowed = {
                "lua", "py", "js", "ts", "svelte", "md", "txt", "json",
                "yaml", "yml", "go", "rs", "java", "html", "css", "sh", "scss", "yuck",
                "php", "no_extension", "sql"
            }
            local filtered = filter_by_extension(all, allowed)
            if #filtered == 0 then
                vim.notify("No files matched allowed extensions", vim.log.levels.INFO)
                return
            end

            -- build markdown and copy
            local root = get_project_root()
            local md   = build_markdown_with_extension_hint(filtered, root)
            vim.fn.setreg("+", md)

            -- Trigger OSC52 for remote clipboard (similar to how yank works)
            if vim.env.SSH_TTY or vim.env.SSH_CLIENT or vim.env.SSH_CONNECTION then
                local function send_osc52(text)
                    local b64 = vim.fn.system({ "base64", "-w0" }, text)
                    vim.fn.chansend(vim.v.stderr, "\x1b]52;c;" .. b64 .. "\x07")
                end
                send_osc52(md)
            end

            Snacks.notify.info(("Copied %d file(s) for LLM"):format(#filtered))
        end

        ---@type snacks.Config
        Snacks.setup({

            -- your configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
            bigfile      = { enabled = true },
            ---@class snacks.dashboard.Config
            dashboard    = {
                enabled = true,
                width = 60,
                row = nil,                                                                   -- dashboard position. nil for center
                col = nil,                                                                   -- dashboard position. nil for center
                pane_gap = 4,                                                                -- empty columns between vertical panes
                autokeys = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", -- autokey sequence
                -- These settings are used by some built-in sections
                preset = {
                    -- Defaults to a picker that supports fzf-lua, telescope.nvim and mini.pick
                    ---@type fun(cmd:string, opts:table)|nil
                    pick = nil,
                    -- Used by the keys section to show keymaps.
                    -- Set your custom keymaps here.
                    -- When using a function, the items argument are the default keymaps.
                    ---@type snacks.dashboard.Item[]
                    keys = {
                        { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
                        { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
                        { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
                        { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
                        { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
                        { icon = " ", key = "s", desc = "Restore Session", section = "session" },
                        { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
                        { icon = " ", key = "q", desc = "Quit", action = ":qa" },
                    },
                },
                -- item field formatters
                formats = {
                    icon = function(item)
                        return { item.icon, width = 2, hl = "icon" }
                    end,
                    footer = { "%s", align = "center" },
                    header = { "%s", align = "center" },
                    file = function(item, ctx)
                        local fname = vim.fn.fnamemodify(item.file, ":~")
                        fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
                        if #fname > ctx.width then
                            local dir = vim.fn.fnamemodify(fname, ":h")
                            local file = vim.fn.fnamemodify(fname, ":t")
                            if dir and file then
                                file = file:sub(-(ctx.width - #dir - 2))
                                fname = dir .. "/…" .. file
                            end
                        end
                        local dir, file = fname:match("^(.*)/(.+)$")
                        return dir and { { dir .. "/", hl = "dir" }, { file, hl = "file" } } or
                            { { fname, hl = "file" } }
                    end,
                },
                sections = {
                    {
                        section = "terminal",
                        cmd = "ascii-image-converter -C -c ~/.config/nvim/header.png",
                        indent = 11,
                        gap = 20,
                        height = 25,
                    },
                    { section = "keys",   gap = 1, padding = 1 },
                    { section = "startup" },
                },
            },
            debug        = { enabled = true },
            explorer     = { enabled = true },
            indent       = { enabled = true },
            input        = { enabled = true },
            picker       = {
                enabled = true,
                formatters = {
                    file = {
                        -- show up to full window width before truncating
                        truncate = vim.o.columns,
                    },
                },
                sources = {
                    explorer = {
                        -- these two come from the SO Q to keep focus on the list pane :contentReference[oaicite:1]{index=1}
                        focus       = "list",
                        auto_close  = true,
                        -- mimic a tree layout without preview panel
                        tree        = true,
                        follow_file = true,
                        layout      = {
                            preview = "main",
                            layout = { position = "left", size = 30 },
                        },
                        actions     = {
                            copy_for_llm = { action = copy_for_llm_action },
                        },
                        win         = {
                            list = {
                                keys = {
                                    ["I"] = "copy_for_llm",
                                    ["/"] = false,
                                    ["?"] = false,
                                },
                            },
                        },
                    },
                },
            },
            notifier     = { enabled = true },
            quickfile    = { enabled = true },
            scope        = { enabled = true },
            scroll       = {
                enabled = true,
                animate = {
                    enable = false, -- Debugging
                    duration = { step = 10, total = 80 },
                    easing = "linear",
                },
            },
            statuscolumn = { enabled = true },
            words        = { enabled = true }
        })
    end
}
