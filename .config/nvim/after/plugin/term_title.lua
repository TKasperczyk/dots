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
local pane_tint  = require("luth.pane_tint")

vim.opt.title    = true
vim.opt.titleold = vim.fn.fnamemodify(vim.env.SHELL or "", ":t")

local POLL_MS = 500

local last
local function sync()
    -- The tint is keyed on the shell's cwd, not the title, so it must be
    -- checked every tick -- a cd can change the project while the title
    -- stays put. apply()/reset() are cheap no-ops when nothing changed.
    -- Only panes hosting a terminal are tinted.
    if term_title.current() then
        pane_tint.apply()
    else
        pane_tint.reset()
    end

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

vim.api.nvim_create_autocmd("VimLeavePre", {
    group    = "TermTitle",
    callback = function() pane_tint.reset() end,
})

-- Nothing fires an autocmd when b:term_title changes, so poll. The handle is
-- kept out of local scope so it is not garbage collected out from under the
-- timer, and so re-sourcing this file stops the previous one instead of
-- stacking a second poller on top of it.
if _G.__term_title_timer then
    pcall(function() _G.__term_title_timer:stop() end)
end
_G.__term_title_timer = (vim.uv or vim.loop).new_timer()
_G.__term_title_timer:start(POLL_MS, POLL_MS, vim.schedule_wrap(sync))
