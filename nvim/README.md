# Neovim Configuration

Modern Neovim configuration for nvim 0.11.5+ with LSP support, completions, and more.

## Features

- **Plugin Manager**: lazy.nvim with automatic plugin installation
- **LSP Support**: Full Language Server Protocol support via mason.nvim
  - Automatic LSP server installation
  - **Languages Supported**:
    - TypeScript/JavaScript (ts_ls)
    - Python (pyright)
    - Ruby (ruby_lsp - requires `gem install ruby-lsp`)
    - Lua (lua_ls)
    - Bash/Shell scripts (bashls)
    - Dockerfile (dockerls)
    - Makefile (autotools_ls)
    - HTML, Tailwind CSS
- **Formatting & Linting**: Modern Rust-based tools for blazing fast performance
  - **Biome** (JS/TS) - 15x faster than ESLint, replaces ESLint + Prettier
  - **Ruff** (Python) - 10-100x faster, replaces pylint + black + isort
  - Stylua (Lua), shfmt (Shell), Prettier (fallback), Shellcheck (Shell)
- **Autocompletion**: nvim-cmp with LSP, buffer, path, and snippet sources
- **File Navigation**: Telescope, Neo-tree, Oil.nvim
- **Git Integration**: Fugitive, Gitsigns, Lazygit
- **AI**: GitHub Copilot support
- **Testing**: vim-test with vimux integration
- **Theme**: Monokai Classic
- **Additional**: Alpha dashboard, Treesitter, and more

## Installation

The configuration will be symlinked to `~/.config/nvim` when you run:

```bash
make personal stow
```

or

```bash
./install.sh -s
```

## Structure

```text
nvim/.config/nvim/
├── init.lua              # Entry point - loads core modules
├── lua/
│   ├── core/             # Core configuration
│   │   ├── options.lua   # Vim options (line numbers, tabs, etc.)
│   │   ├── keymaps.lua   # Global keymaps
│   │   └── lazy.lua      # lazy.nvim bootstrap and setup
│   └── plugins/          # Plugin configurations
│       ├── lsp/          # LSP-specific plugins
│       │   ├── mason.lua      # LSP server management
│       │   └── lspconfig.lua  # LSP configuration and keymaps
│       ├── alpha.lua
│       ├── monokai.lua
│       ├── completions.lua
│       ├── copilot.lua
│       ├── git-stuff.lua
│       ├── gitsigns.lua
│       ├── lazygit.lua
│       ├── neo-tree.lua
│       ├── none-ls.lua
│       ├── nvim-tmux-navigation.lua
│       ├── oil.lua
│       ├── swagger-preview.lua
│       ├── telescope.lua
│       ├── treesitter.lua
│       └── vim-test.lua
└── lazy-lock.json        # Plugin version lock file
```

## First Run

On first run, lazy.nvim will:

1. Bootstrap itself (auto-install)
2. Install all configured plugins
3. Mason will install configured LSP servers

This process is automatic and may take a few minutes.

## LSP Keymaps

When an LSP server attaches to a buffer, these keymaps become available:

| Key          | Action                                |
| ------------ | ------------------------------------- |
| `gR`         | Show LSP references (Telescope)       |
| `gD`         | Go to declaration                     |
| `gd`         | Show LSP definitions (Telescope)      |
| `gi`         | Show LSP implementations (Telescope)  |
| `gt`         | Show LSP type definitions (Telescope) |
| `<leader>ca` | Code actions                          |
| `<leader>rn` | Rename symbol                         |
| `<leader>D`  | Show buffer diagnostics (Telescope)   |
| `<leader>d`  | Show line diagnostics                 |
| `[d`         | Previous diagnostic                   |
| `]d`         | Next diagnostic                       |
| `K`          | Hover documentation                   |
| `<leader>gf` | Format file                           |
| `<leader>rs` | Restart LSP                           |

## Core Keymaps

| Key                | Action                                                 |
| ------------------ | ------------------------------------------------------ |
| `jk` (insert mode) | Exit insert mode (ergonomic ESC alternative)           |
| `<leader>h`        | Clear search highlights                                |
| `<C-h/j/k/l>`      | Navigate between windows (see Navigation Layers below) |
| `<leader>sv`       | Split window vertically                                |
| `<leader>sh`       | Split window horizontally                              |
| `<leader>se`       | Make splits equal size                                 |
| `<leader>sx`       | Close current split                                    |
| `<leader>to`       | Open new tab                                           |
| `<leader>tx`       | Close current tab                                      |
| `<leader>tn`       | Go to next tab                                         |
| `<leader>tp`       | Go to previous tab                                     |
| `<leader>tf`       | Open current buffer in new tab                         |

Leader key is `<Space>`.

## Navigation Layers

This configuration supports three distinct navigation layers:

### 1. Neovim Tabs (Internal to Neovim)

**Keymaps**: `<leader>t*` commands listed above

**What they are**: Neovim's built-in tab pages - separate workspaces within a single nvim instance.
Each tab can contain multiple windows/splits.

**Scope**: Works in any terminal emulator (Ghostty, iTerm2, Alacritty, etc.) and with or without tmux.

**Example**: Open `file1.rb` in tab 1, `file2.rb` in tab 2 within the same nvim instance.

### 2. Window/Split Navigation (Nvim + Tmux Integration)

**Keymaps**: `<C-h/j/k/l>` for navigation, `<leader>s*` for split management

**Plugin**: `nvim-tmux-navigation` provides seamless navigation across tmux/nvim boundary

**Behavior**:

- **With tmux**: Navigate between tmux panes AND nvim splits with the same keys
- **Without tmux**: Navigate between nvim splits only

**Example**: Split nvim vertically (`<leader>sv`), navigate with `<C-l>` and `<C-h>`

### 3. Terminal Tabs (Terminal Emulator)

**Keymaps**: Terminal-specific (e.g., `Cmd-t` in Ghostty/iTerm2)

**What they are**: Your terminal emulator's native tabs (completely separate from Neovim)

**Scope**: Each terminal tab can run a different program (nvim, shell, etc.)

This layered approach allows you to organize your workspace at multiple levels depending on your needs.

## Language-Specific Setup

### Ruby

Ruby LSP requires the gem to be installed:

```bash
gem install ruby-lsp
```

### Python

Pyright uses your system Python. For project-specific dependencies, ensure you're in a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate  # On macOS/Linux
```

Pyright will automatically detect the virtual environment.

**Ruff** provides ultra-fast linting and formatting (10-100x faster than pylint/black). It's configured to run automatically and replaces:

- black (formatter)
- isort (import sorter)
- pylint (linter)
- flake8, pyupgrade, and more

### TypeScript/JavaScript

ts_ls requires Node.js and will work with any project that has a `package.json`.

**Biome** is a Rust-based linter and formatter that's 15x faster than ESLint. It provides:

- Near-instant linting feedback (200ms vs 3-5s for ESLint on large codebases)
- 97% Prettier-compatible formatting
- Multi-threaded performance (uses all CPU cores)
- Combined linting + formatting in one tool

Note: Biome covers ~80% of ESLint rules. For projects requiring specialized ESLint plugins, Prettier can be used as a fallback.

### Shell Scripts

bashls works with `.sh`, `.bash`, and `.zsh` files. shellcheck linting is automatically enabled.

### Docker & Makefiles

dockerls and autotools_ls work out of the box with `Dockerfile` and `Makefile` respectively.

## Adding More LSP Servers

To add a new LSP server:

1. Edit `lua/plugins/lsp/mason.lua`
2. Add the server name to `ensure_installed` list in `mason_lspconfig.setup()`
3. Optionally add language-specific configuration in `lua/plugins/lsp/lspconfig.lua`
4. Restart nvim or run `:Lazy sync`

Example:

```lua
ensure_installed = {
  "lua_ls",
  "rust_analyzer",  -- Add Rust LSP
}
```

Then configure it in lspconfig.lua if needed:

```lua
vim.lsp.config("rust_analyzer", {
  settings = {
    ["rust-analyzer"] = {
      cargo = { allFeatures = true },
    },
  },
})
```

## Updating Plugins

```vim
:Lazy update
```

Or from command line:

```bash
nvim --headless +'Lazy update' +qa
```

## Troubleshooting

### Check LSP status

```vim
:LspInfo
```

### Check Mason installations

```vim
:Mason
```

### Check plugin status

```vim
:Lazy
```

### View logs

```vim
:messages
```

## Compatibility

- **Neovim**: 0.11.5+ (tested on 0.11.5)
- **OS**: macOS (primary), Linux compatible
- **Dependencies**: git, ripgrep (for Telescope), a Nerd Font (for icons)

## Best Practices Analysis

This configuration follows modern Neovim best practices based on analysis of popular community configs (josean-dev):

### Already Implemented

1. **Modern LSP Setup (0.11+)**

   - Uses `vim.lsp.config()` API instead of deprecated `setup_handlers()`
   - Uses `vim.diagnostic.config()` for diagnostic signs (not `vim.fn.sign_define()`)
   - Proper dependency chain: mason.nvim → mason-lspconfig → lspconfig

2. **Modular Structure**

   - `core/` for Neovim settings (options, keymaps, lazy bootstrap)
   - `plugins/` for plugin specs with automatic discovery
   - `plugins/lsp/` for LSP-specific configurations

3. **Lazy Loading**

   - Plugins load on events (`InsertEnter`, `BufReadPre`, etc.)
   - Auto-completion only loads when entering insert mode
   - LSP loads before file buffers open

4. **Configuration Quality**
   - All keymaps have descriptions for discoverability
   - Leader key set before lazy.nvim loads (in options.lua)
   - Error handling in lazy.nvim bootstrap
   - Lock file for reproducible plugin versions

### Differences from Reference Config (Intentional)

1. **Keymap: Exit Insert Mode**

   - **Josean**: `jk` → `<ESC>` (common vim community pattern)
   - **Our config**: Not implemented (prefer standard `<ESC>` or `<C-c>`)
   - **Recommendation**: Add if you like the ergonomics

2. **Keymap: Number Increment/Decrement**

   - **Josean**: `<leader>+` and `<leader>-` for increment/decrement
   - **Our config**: Use default `<C-a>` and `<C-x>`
   - **Recommendation**: Keep defaults (muscle memory from standard Vim)

3. **Keymap: Clear Search**

   - **Josean**: `<leader>nh` (mnemonic: "no highlight")
   - **Our config**: `<leader>h`
   - **Status**: Both valid, ours is more concise

4. **Tab Management**

   - **Josean**: Has `<leader>tf` to open current buffer in new tab
   - **Our config**: Missing this keymap
   - **Recommendation**: Consider adding if you use tabs heavily

5. **Advanced Options**
   - **Our config**: Includes `scrolloff = 8`, `smartindent`, `softtabstop`
   - **Josean**: Minimal options set
   - **Status**: Our config is more opinionated (good)

### Recent Fixes (2025-01-10)

- Fixed `vim.tbl_add_reverse_lookup` deprecation warnings
- Migrated from `mason_lspconfig.setup_handlers()` to `vim.lsp.config()`
- Modernized diagnostic sign configuration
- Updated lazy.nvim bootstrap with better error handling
- Better plugin organization (core/ and plugins/lsp/ separation)
- Ruby LSP now works properly with rbenv

### Config Comparison Summary

| Feature             | Our Config         | Josean             | Status             |
| ------------------- | ------------------ | ------------------ | ------------------ |
| LSP API             | `vim.lsp.config()` | `vim.lsp.config()` | Modern             |
| Lazy loading        | Yes                | Yes                | Optimal            |
| Modular structure   | Yes                | Yes                | Clean              |
| Keymap descriptions | Yes                | Yes                | Discoverable       |
| Extra options       | More               | Minimal            | Opinionated (good) |
| Completion setup    | Identical          | Identical          | Perfect            |

**Conclusion**: Our configuration is already following best practices and is more feature-complete than the reference. The recent LSP API migration brought us fully up to date with Neovim 0.11+ standards.
