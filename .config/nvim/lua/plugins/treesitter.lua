-- main branch (rewrite): master is frozen upstream and incompatible with nvim 0.12
-- (match[id] became a list of nodes; master's query predicates call :range() on it,
--  causing "attempt to call method 'range' (a nil value)" on markdown code blocks)
local ensure_installed = {
    "javascript", "typescript", "svelte", "c", "lua", "vim",
    "vimdoc", "query", "markdown", "markdown_inline",
}

local M = {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        require("nvim-treesitter").install(ensure_installed)

        -- main branch no longer auto-starts highlighting; enable it per buffer
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("treesitter.highlight", { clear = true }),
            callback = function(ev)
                local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
                if lang then
                    pcall(vim.treesitter.start, ev.buf, lang)
                end
            end,
        })
    end,
}

return { M }
