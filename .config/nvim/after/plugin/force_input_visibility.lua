-- Fix Snacks.input and vim.ui.input z-index layering issue
vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    callback = function()
        vim.defer_fn(function()
            -- Create a shared input function with high z-index
            local function create_visible_input(opts, on_confirm)
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
                
                -- Set initial value if provided
                if opts.default then
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
                    vim.fn.prompt_setprompt(buf, "")
                else
                    vim.fn.prompt_setprompt(buf, "> ")
                end
                
                -- Handle input completion
                vim.fn.prompt_setcallback(buf, function(text)
                    vim.api.nvim_win_close(win, true)
                    vim.api.nvim_buf_delete(buf, { force = true })  -- Clean up the buffer
                    if on_confirm then
                        on_confirm(text)
                    end
                end)
                
                -- Handle escape to cancel
                vim.keymap.set("n", "<Esc>", function()
                    vim.api.nvim_win_close(win, true)
                    vim.api.nvim_buf_delete(buf, { force = true })  -- Clean up the buffer
                    if on_confirm then
                        on_confirm(nil)
                    end
                end, { buffer = buf })
                
                -- Also handle escape in insert mode
                vim.keymap.set("i", "<Esc>", function()
                    vim.cmd("stopinsert")
                    vim.api.nvim_win_close(win, true)
                    vim.api.nvim_buf_delete(buf, { force = true })  -- Clean up the buffer
                    if on_confirm then
                        on_confirm(nil)
                    end
                end, { buffer = buf })
                
                vim.cmd("startinsert")
                
                -- If there's default text, move cursor to end
                if opts.default then
                    vim.cmd("normal! $")
                end
            end
            
            -- Override Snacks.input
            if Snacks and Snacks.input then
                Snacks.input = create_visible_input
            end
            
            -- Also override vim.ui.input for rename and other operations
            vim.ui.input = create_visible_input
        end, 100)
    end,
})