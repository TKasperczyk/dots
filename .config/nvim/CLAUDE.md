# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Plugin Management
- **Install/Update plugins**: Open Neovim and run `:Lazy sync`
- **Check plugin status**: `:Lazy`
- **Update plugin lock file**: `:Lazy update` then commit `lazy-lock.json`

### Development
- **Format current file**: `:lua vim.lsp.buf.format()` or wait for auto-format on save
- **Check LSP status**: `:LspInfo`
- **Restart LSP**: `:LspRestart`

## Architecture

### Configuration Structure
This is a modular Neovim configuration using lazy.nvim for plugin management. The configuration follows this hierarchy:

1. `init.lua` → `lua/luth/init.lua` (main orchestrator)
2. Core modules in `lua/luth/`:
   - `set.lua`: Neovim settings
   - `remap.lua`: Custom keybindings
   - `lazy.lua`: Plugin manager setup
3. Plugin configurations in `lua/plugins/`: Each plugin has its own file

### Key Design Decisions

**LSP Configuration**: The setup intelligently handles TypeScript/JavaScript projects:
- Uses `vtsls` for Node.js projects (presence of `node_modules`)
- Uses `denols` for Deno projects (presence of `deno.json`)
- Never runs both simultaneously to avoid conflicts

**Clipboard Integration**: Enhanced clipboard support for remote sessions:
- System clipboard integration via `unnamedplus`
- OSC52 support for SSH sessions (see `after/plugin/osc52_clipboard.lua`)
- Custom yank behavior that syncs with system clipboard

**Plugin Architecture**: Each plugin configuration returns a lazy.nvim spec with:
- Plugin identifier
- Dependencies
- Configuration functions
- Lazy loading conditions

### Important Files
- `lua/plugins/lsp.lua`: Language server configurations
- `lua/plugins/completion.lua`: Blink.cmp completion setup
- `lua/plugins/snacks.lua`: Multi-feature utility plugin (file explorer, git, dashboard)
- `after/plugin/osc52_clipboard.lua`: Remote clipboard support

### Working with Plugins
When adding new plugins:
1. Create a new file in `lua/plugins/`
2. Return a table with the plugin spec
3. The file will be automatically loaded by lazy.nvim

When modifying keybindings:
- Core remaps: Edit `lua/luth/remap.lua`
- Plugin-specific: Edit the respective plugin file in `lua/plugins/`

### Known Issues and Fixes

**Terminal Transparency Issue**: The terminal's transparency settings override floating window backgrounds, making them invisible even when Neovim sets solid background colors. This affects:
- Snacks input dialogs (file creation, renaming, etc.)
- Any plugin using `vim.ui.input`

**Solution**: `after/plugin/snacks_input_fix.lua` replaces all floating input dialogs with command-line input, which is always visible.