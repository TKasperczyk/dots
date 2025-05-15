function _G.switch_onedark_style(style)
    require("onedark").setup({ style = style })
    vim.cmd("colorscheme onedark")
    require("lualine").setup(require("lualine").get_config())
end -- update config table

return {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
        local onedark = require("onedark")

        -- initial setup: darker in Normal
        onedark.setup {
            style = "darker",
            transparent = true,
            term_colors = false,
            ending_tildes = false,
            cmp_itemkind_reverse = false,

            -- code styling, lualine, diagnostics, etc.
            code_style = {
                comments  = "italic",
                keywords  = "none",
                functions = "none",
                strings   = "none",
                variables = "none",
            },
            lualine = { transparent = true },
            diagnostics = { darker = true, undercurl = true, background = true },
        }
        onedark.load()

        -- when you enter Insert mode → switch to “dark”
        vim.api.nvim_create_autocmd("InsertEnter", {
            callback = function()
                -- reset the style and reload the theme
                --switch_onedark_style("darker")
            end,
        })

        -- when you leave Insert mode → go back to “darker”
        vim.api.nvim_create_autocmd("InsertLeave", {
            callback = function()
                --switch_onedark_style("dark")
            end,
        })
    end,
}
