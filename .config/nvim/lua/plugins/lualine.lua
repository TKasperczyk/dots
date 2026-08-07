return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
        local term_title = require("luth.term_title")
        local pane_tint  = require("luth.pane_tint")

        -- In a terminal buffer, "filename" is just "zsh", which is useless when
        -- several panes are running Claude side by side. Show what the nested
        -- program set as its OSC title instead.
        local MAX_TITLE_LEN = 48

        local session_title = function()
            local title = term_title.current()
            if not title then
                return ""
            end
            if #title > MAX_TITLE_LEN then
                title = title:sub(1, MAX_TITLE_LEN - 1) .. "…"
            end
            return title
        end

        local in_terminal = function()
            return term_title.current() ~= nil
        end

        -- Custom Lualine component to show attached language server
        local clients_lsp = function()
            local bufnr = vim.api.nvim_get_current_buf()

            local clients = vim.lsp.get_clients()
            if next(clients) == nil then
                return ""
            end

            local c = {}
            for _, client in pairs(clients) do
                table.insert(c, client.name)
            end
            return " " .. table.concat(c, "|")
        end

        require("lualine").setup({
            options = {
                component_separators = "",
                section_separators = { left = "", right = "" },
                disabled_filetypes = { "alpha", "Outline" },
            },
            sections = {
                lualine_a = {
                    { "mode", separator = { left = " ", right = "" }, icon = "" },
                },
                lualine_b = {
                    {
                        "filetype",
                        icon_only = true,
                        padding = { left = 1, right = 0 },
                    },
                    {
                        session_title,
                        cond = in_terminal,
                        -- The session's identity block: family hue at full
                        -- vividness, per-shade lightness. The dark background
                        -- wash alone is too subtle to tell panes apart.
                        color = function()
                            local accent = pane_tint.accent()
                            if not accent then return nil end
                            return { bg = accent.bg, fg = accent.fg, gui = "bold" }
                        end,
                    },
                    { "filename", cond = function() return not in_terminal() end },
                },
                lualine_c = {
                    {
                        "branch",
                        icon = "",
                    },
                    {
                        "diff",
                        symbols = { added = " ", modified = " ", removed = " " },
                        colored = false,
                    },
                },
                lualine_x = {
                    {
                        "diagnostics",
                        symbols = { error = " ", warn = " ", info = " ", hint = " " },
                        update_in_insert = true,
                    },
                },
                lualine_y = { clients_lsp },
                lualine_z = {
                    { "location", separator = { left = "", right = " " }, icon = "" },
                },
            },
            inactive_sections = {
                lualine_a = { "filename" },
                lualine_b = {},
                lualine_c = {},
                lualine_x = {},
                lualine_y = {},
                lualine_z = { "location" },
            },
            extensions = { "toggleterm", "trouble" },
        })
    end,
}
