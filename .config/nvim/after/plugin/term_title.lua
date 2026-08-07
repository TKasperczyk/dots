-- Forward a terminal buffer's OSC 0/2 title out to the real terminal emulator.
-- nvim captures titles set by nested programs (Claude Code, ssh, ...) into
-- b:term_title and stops there, so every kitty/Terminator tab just reads "nvim"
-- and parallel Claude sessions are indistinguishable.
--
-- nvim never recalculates the window title when b:term_title changes, and %{}
-- expressions in 'titlestring' are not re-evaluated on that event either, so
-- poll instead and assign a plain string -- the assignment is what forces the
-- title redraw.

local term_title = require("luth.term_title")

vim.opt.title    = true
vim.opt.titleold = vim.fn.fnamemodify(vim.env.SHELL or "", ":t")

local POLL_MS = 500

local last
local function sync()
    local title = term_title.window()
    if title == last then return end
    last = title
    -- 'titlestring' expands statusline items, so a literal % has to be doubled.
    vim.opt.titlestring = title:gsub("%%", "%%%%")
end

vim.api.nvim_create_augroup("TermTitle", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "TermOpen", "DirChanged" }, {
    group    = "TermTitle",
    callback = sync,
})

-- Nothing fires an autocmd when b:term_title changes, so poll. The handle is
-- kept in a local so it is not garbage collected out from under the timer.
local timer = (vim.uv or vim.loop).new_timer()
timer:start(POLL_MS, POLL_MS, vim.schedule_wrap(sync))
