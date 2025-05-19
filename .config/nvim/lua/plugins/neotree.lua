local Path = require("plenary.path")

-- Helper: Find the project root (git or cwd fallback)
local function get_project_root()
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
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

-- Build markdown string for a list of files
local function build_markdown(files, root)
    local out = {}
    for _, abs_path in ipairs(files) do
        local rel_path = Path:new(abs_path):make_relative(root)
        local f = io.open(abs_path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            table.insert(out, ("# %s\n```%s\n```\n"):format(rel_path, content or ""))
        end
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

    -- First collect all selected node paths
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
end -- Normal mode
local function copy_file_for_llm(state)
    local root = get_project_root()
    local files = gather_selected_files({ state.tree:get_node() })
    local content = build_markdown(files, root)
    vim.fn.setreg("+", content)
    vim.notify(("Copied %d file(s) to clipboard"):format(#files), vim.log.levels.INFO)
end

-- Visual mode
local function copy_file_for_llm_visual(state, selected_nodes)
    local root = get_project_root()
    local files = gather_selected_files(selected_nodes)
    local content = build_markdown(files, root)
    vim.fn.setreg("+", content)
    vim.notify(("Copied %d file(s) to clipboard"):format(#files), vim.log.levels.INFO)
end

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    config = function()
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
