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

    -- Build server list based on available tools
    local ensure_installed = {
      -- Core development
      "lua_ls",         -- Lua
      "ruby_lsp",       -- Ruby

      -- Web development (Node.js-independent)
      "html",           -- HTML

      -- Python
      "pyright",        -- Python type checking and completion

      -- Shell & DevOps
      "bashls",         -- Bash/shell scripts
      "dockerls",       -- Dockerfile
      "autotools_ls",   -- Makefile
    }

    -- Add Node.js-dependent servers if npm is available
    if vim.fn.executable("npm") == 1 then
      table.insert(ensure_installed, "tailwindcss")  -- Tailwind CSS
      table.insert(ensure_installed, "ts_ls")        -- TypeScript/JavaScript
    end

    mason_lspconfig.setup({
      ensure_installed = ensure_installed,
      -- Auto-install configured servers (with lspconfig)
      automatic_installation = true,
    })

    -- Build tool list based on available tools
    local ensure_tools = {
      -- Formatters
      "stylua",         -- Lua formatter
      "shfmt",          -- Shell script formatter

      -- Modern Rust-based tools (10-100x faster)
      "ruff",           -- Python linter + formatter (replaces black, isort, pylint)

      -- Additional linters
      "shellcheck",     -- Shell script linter
    }

    -- Add Node.js-dependent tools if npm is available
    if vim.fn.executable("npm") == 1 then
      table.insert(ensure_tools, "prettier")  -- JS/TS/HTML/CSS formatter
      table.insert(ensure_tools, "biome")     -- JS/TS linter + formatter
    end

    mason_tool_installer.setup({
      ensure_installed = ensure_tools,
    })
  end,
}
