-- What is this pane actually doing? Nested programs (Claude Code, ssh, ...) set
-- an OSC 0/2 title that nvim captures into b:term_title and then sits on.
-- Shared by after/plugin/term_title.lua (forwards it to the terminal emulator)
-- and the lualine config (renders it in the statusline).

local M = {}

-- Claude Code prefixes its topic with a status glyph (✳ / a braille spinner)
-- that changes several times a second; strip it so the label stays stable.
local function strip_status_glyph(title)
    return (title:gsub("^[^%a%d]*%s+", ""))
end

-- The nested program's title, or nil when this is not a terminal buffer.
function M.current()
    local term = vim.b.term_title
    if term and term ~= "" then
        return strip_status_glyph(term)
    end
    return nil
end

-- Same, but always returns something -- for use as the window title.
function M.window()
    local title = M.current()
    if title then return title end

    local name = vim.fn.expand("%:t")
    if name ~= "" then return name end

    return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
end

return M
