-- only run over SSH
if not (vim.env.SSH_TTY or vim.env.SSH_CLIENT or vim.env.SSH_CONNECTION) then
    return
end

local function send_osc52(text)
    local b64 = vim.fn.system({ "base64", "-w0" }, text)
    -- ESC ] 52 ; c ; <b64> BEL
    vim.fn.chansend(vim.v.stderr, "\x1b]52;c;" .. b64 .. "\x07")
end

-- yank → OSC52
vim.api.nvim_create_augroup("OSC52Yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
    group = "OSC52Yank",
    callback = function()
        if vim.v.event.operator ~= "y" then return end
        -- first try the + register (unnamedplus)
        local txt = vim.fn.getreg("+")
        if txt == "" then
            -- fall back to the unnamed register
            txt = vim.fn.getreg('"')
        end
        if txt == "" then return end
        send_osc52(txt)
    end,
})
