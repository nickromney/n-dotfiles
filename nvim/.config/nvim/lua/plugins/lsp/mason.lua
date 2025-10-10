return {
  "williamboman/mason.nvim",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    local mason = require("mason")
    local mason_lspconfig = require("mason-lspconfig")
    local mason_tool_installer = require("mason-tool-installer")

    -- Enable mason
    mason.setup({
      ui = {
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    })

    mason_lspconfig.setup({
      -- List of servers for mason to install
      ensure_installed = {
        -- Core development
        "lua_ls",         -- Lua
        "ruby_lsp",       -- Ruby

        -- Web development
        "html",           -- HTML
        "tailwindcss",    -- Tailwind CSS
        "ts_ls",          -- TypeScript/JavaScript

        -- Python
        "pyright",        -- Python type checking and completion

        -- Shell & DevOps
        "bashls",         -- Bash/shell scripts
        "dockerls",       -- Dockerfile
        "autotools_ls",   -- Makefile
      },
      -- Auto-install configured servers (with lspconfig)
      automatic_installation = true,
    })

    mason_tool_installer.setup({
      ensure_installed = {
        -- Formatters
        "stylua",         -- Lua formatter
        "prettier",       -- JS/TS/HTML/CSS formatter (fallback for unsupported files)
        "shfmt",          -- Shell script formatter

        -- Modern Rust-based tools (10-100x faster)
        "ruff",           -- Python linter + formatter (replaces black, isort, pylint)
        "biome",          -- JS/TS linter + formatter (replaces ESLint + Prettier)

        -- Additional linters
        "shellcheck",     -- Shell script linter
      },
    })
  end,
}
