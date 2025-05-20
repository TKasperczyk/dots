-- Your original functions:
local Path = require("plenary.path")

-- Helper: Find the project root (git or cwd fallback)
local function get_project_root()
    local git_root_lines = vim.fn.systemlist("git rev-parse --show-toplevel")
    local git_root = git_root_lines and git_root_lines[1]

    if git_root and git_root ~= "" then
        return git_root
    end
    return vim.loop.cwd()
end

-- Recursively collect all files under a path (file or dir)
local function collect_files(path)
    local files = {}
    local stat = vim.loop.fs_stat(path)
    if not stat then return files end

    if stat.type == "file" then
        table.insert(files, path)
    elseif stat.type == "directory" then
        for _, entry in ipairs(vim.fn.readdir(path) or {}) do
            if entry ~= "." and entry ~= ".." then
                local child = Path:new(path) / entry
                for _, f in ipairs(collect_files(child:absolute())) do
                    table.insert(files, f)
                end
            end
        end
    end
    return files
end

local function get_final_extension(filename_str)
    if type(filename_str) ~= "string" or filename_str == "" then
        return ""
    end
    -- Find the position of the last dot
    local last_dot_position
    for i = #filename_str, 1, -1 do
        if filename_str:sub(i, i) == '.' then
            last_dot_position = i
            break
        end
    end

    if last_dot_position and last_dot_position > 1 and last_dot_position < #filename_str then
        -- Dot is not the first character (e.g. .bashrc) and not the last (e.g. file.)
        return filename_str:sub(last_dot_position + 1)
    elseif last_dot_position and last_dot_position == 1 and #filename_str > 1 then
        -- File like .bashrc, consider it as having no "traditional" extension for filtering purposes
        return ""
    end
    return "" -- No dot found, or dot is the last character
end



-- Modified build_markdown for extension hint
local function build_markdown_with_extension_hint(files, root_path_str)
    local out = {}
    local root_p = Path:new(root_path_str)
    if not root_p then
        vim.notify("build_markdown: Invalid root path: " .. vim.inspect(root_path_str), vim.log.levels.ERROR)
        return ""
    end

    for _, file_path_str in ipairs(files) do
        if type(file_path_str) == "string" and file_path_str ~= "" then
            local file_p_obj = Path:new(file_path_str)
            if not file_p_obj then
                vim.notify("build_markdown: Path:new() for file_path_str failed. Path: " .. vim.inspect(file_path_str),
                    vim.log.levels.ERROR)
                goto continue_loop_bm
            end

            local abs_file_path_str = file_p_obj:absolute()
            local rel_path_str = Path:new(abs_file_path_str):make_relative(root_p:absolute())

            local file_extension_val = get_final_extension(file_p_obj.filename) -- Use new helper
            local file_extension_lower = file_extension_val:lower()
            if file_extension_lower == "" then file_extension_lower = "text" end

            local content = ""
            local f = io.open(abs_file_path_str, "rb")
            if f then
                content = f:read("*a")
                f:close()
                if string.find(content, "\0") then
                    vim.notify(
                        "Warning: File " .. abs_file_path_str .. " contains null bytes (binary). Omitting content.",
                        vim.log.levels.WARN, { title = "LLM Copy" })
                    content = "[Content of binary file " .. file_p_obj.filename .. " omitted]"
                end
            else
                vim.notify("Could not open file for markdown: " .. abs_file_path_str, vim.log.levels.WARN)
                content = "[Could not read file " .. file_p_obj.filename .. "]"
            end
            table.insert(out, ("# %s\n```%s\n%s\n```\n"):format(rel_path_str, file_extension_lower, content))
        else
            vim.notify("Skipping invalid/nil path in build_markdown: " .. vim.inspect(file_path_str), vim.log.levels
                .WARN)
        end
        ::continue_loop_bm::
    end
    return table.concat(out, "\n")
end


-- Gather selected files (handles files/dirs/nodes)
local function is_child_of_any(path, parent_paths)
    for _, parent in ipairs(parent_paths) do
        if parent ~= path and vim.startswith(path, parent .. "/") then
            return true
        end
    end
    return false
end

local function gather_selected_files(nodes)
    local all_files = {}
    local seen = {}
    local selected_paths = {}

    for _, node in ipairs(nodes) do
        if type(node) == "table" and node.path then
            table.insert(selected_paths, node.path)
        end
    end

    for _, node in ipairs(nodes) do
        if type(node) == "table" and node.path then
            if not is_child_of_any(node.path, selected_paths) then
                local paths = collect_files(node.path)
                for _, p in ipairs(paths) do
                    if not seen[p] then
                        table.insert(all_files, p)
                        seen[p] = true
                    end
                end
            end
        end
    end
    return all_files
end

-- End of your original functions

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    config = function()
        local yank_llm_allowed_extensions = {
            "lua", "py", "js", "ts", "svelte", "md", "txt", "json", "yaml", "yml", "go", "rs", "java", "html", "css",
            "sh", "php",
            "no_extension",
        }
        -- vim.notify("LLM Copy Allowed Extensions: " .. vim.inspect(yank_llm_allowed_extensions), vim.log.levels.INFO)


        local function filter_by_extension(files_list, allowed_extensions_config)
            if not allowed_extensions_config or #allowed_extensions_config == 0 then
                return files_list
            end

            local filtered = {}
            local allowed_map = {}
            for _, ext_str in ipairs(allowed_extensions_config) do
                allowed_map[ext_str:lower()] = true
            end

            for _, file_path_str_from_list in ipairs(files_list) do
                if type(file_path_str_from_list) ~= "string" or file_path_str_from_list == "" then
                    goto continue_filter_loop
                end

                local file_p_obj = Path:new(file_path_str_from_list)
                if not file_p_obj then
                    goto continue_filter_loop
                end

                -- Use the new helper function to get the extension
                local actual_file_extension_val = get_final_extension(file_p_obj.filename)
                local actual_file_extension_lower = actual_file_extension_val:lower()

                local is_allowed_by_filter = false
                if allowed_map[actual_file_extension_lower] then
                    is_allowed_by_filter = true
                elseif actual_file_extension_val == "" and allowed_map["no_extension"] then
                    -- This condition means the filename TRULY has no dots (or only at the beginning)
                    is_allowed_by_filter = true
                end

                if is_allowed_by_filter then
                    table.insert(filtered, file_path_str_from_list)
                end
                ::continue_filter_loop::
            end
            return filtered
        end

        local function copy_file_for_llm(state)
            local root_path = get_project_root()
            local node_to_process = state.tree:get_node()
            if not node_to_process or not node_to_process.path then
                vim.notify("No node selected or node has no path.", vim.log.levels.WARN, { title = "Neo-tree LLM Copy" })
                return
            end

            local collected_files = gather_selected_files({ node_to_process })
            local files_to_copy = filter_by_extension(collected_files, yank_llm_allowed_extensions)

            if #files_to_copy == 0 then
                local msg_detail = #collected_files > 0 and "allowed extensions." or "in selection (or none matched)."
                vim.notify("No files matched " .. msg_detail .. " Copied 0 files.", vim.log.levels.INFO,
                    { title = "Neo-tree LLM Copy" })
                return
            end

            local absolute_root_path = Path:new(root_path):absolute()
            local content = build_markdown_with_extension_hint(files_to_copy, absolute_root_path)

            vim.fn.setreg("+", content)
            vim.notify(("Copied %d file(s) (matching extensions) to clipboard"):format(#files_to_copy),
                vim.log.levels.INFO, { title = "Neo-tree LLM Copy" })
        end

        local function copy_file_for_llm_visual(state, selected_nodes)
            if not selected_nodes or #selected_nodes == 0 then
                vim.notify("No nodes selected in visual mode.", vim.log.levels.WARN, { title = "Neo-tree LLM Copy" })
                return
            end
            local root_path = get_project_root()
            local collected_files = gather_selected_files(selected_nodes)
            local files_to_copy = filter_by_extension(collected_files, yank_llm_allowed_extensions)

            if #files_to_copy == 0 then
                local msg_detail = #collected_files > 0 and "allowed extensions from visual selection." or
                    "in visual selection (or none matched)."
                vim.notify("No files matched " .. msg_detail .. " Copied 0 files.", vim.log.levels.INFO,
                    { title = "Neo-tree LLM Copy" })
                return
            end

            local absolute_root_path = Path:new(root_path):absolute()
            local content = build_markdown_with_extension_hint(files_to_copy, absolute_root_path)

            vim.fn.setreg("+", content)
            vim.notify(
                ("Copied %d file(s) (matching extensions) from visual selection to clipboard"):format(#files_to_copy),
                vim.log.levels.INFO, { title = "Neo-tree LLM Copy" })
        end

        require("neo-tree").setup({
            close_if_last_window = true,
            popup_border_style   = "rounded",
            filesystem           = {
                follow_current_file = { leave_dirs_open = false, enabled = true },
                use_libuv_file_watcher = true,
                commands = {
                    copy_file_for_llm = copy_file_for_llm,
                    copy_file_for_llm_visual = copy_file_for_llm_visual,
                },
                window = {
                    mappings = {
                        ["/"] = "noop",
                        ["?"] = "noop",
                        ["I"] = "copy_file_for_llm",
                        ["I_visual"] = "copy_file_for_llm_visual",
                    },
                    popup = {
                        title = "",
                        size = { width = 120, height = 50 },
                        position = "50%",
                    },
                    auto_expand_width = true,
                    position = "float",
                },
            },
        })
    end,
}
