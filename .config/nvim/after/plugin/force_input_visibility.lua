-- Fix Snacks.input z-index layering issue
vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    callback = function()
        vim.defer_fn(function()
            if Snacks and Snacks.input then
                -- Override Snacks.input to fix z-index layering
                Snacks.input = function(opts, on_confirm)
                    local buf = vim.api.nvim_create_buf(false, true)
                    local width = 80  -- Wider default
                    local height = 1
                    
                    local win = vim.api.nvim_open_win(buf, true, {
                        relative = "editor",
                        width = width,
                        height = height,
                        row = 2,  -- Default position
                        col = math.floor((vim.o.columns - width) / 2),
                        border = "rounded",
                        title = opts.prompt or "Input",  -- Use prompt as window title
                        title_pos = "center",
                        zindex = 9999,  -- Key fix: high z-index
                    })
                    
                    -- Set buffer options for input
                    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
                    vim.fn.prompt_setprompt(buf, "> ")  -- Simple prompt
                    
                    -- Handle input completion
                    vim.fn.prompt_setcallback(buf, function(text)
                        vim.api.nvim_win_close(win, true)
                        if on_confirm then
                            on_confirm(text)
                        end
                    end)
                    
                    -- Handle escape to cancel
                    vim.keymap.set("n", "<Esc>", function()
                        vim.api.nvim_win_close(win, true)
                        if on_confirm then
                            on_confirm(nil)
                        end
                    end, { buffer = buf })
                    
                    vim.cmd("startinsert")
                end
            end
        end, 100)
    end,
})