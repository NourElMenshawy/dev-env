--[[
=====================================================================
==================== KICKSTART PRESENTS          ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   NELMENSH .NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:mason.lua          ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==neio==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================
--]]

return { 
  "williamboman/mason.nvim",
  dependencies = {
  --  "williamboman/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim", -- tools (formatters/linters)
    "jay-babu/mason-nvim-dap.nvim",              -- debug adapters
  },
  config = function()
    local mason            = require("mason")
   --local mason_lspconfig  = require("mason-lspconfig")
    local mason_tools      = require("mason-tool-installer")
    local mason_dap        = require("mason-nvim-dap")

    mason.setup({
      ui = {
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    })

    -- LSP servers
    -- mason_lspconfig.setup({
    --   ensure_installed = {
    --     
    --     -- C/C++ & build system
    --     "clangd",      -- C/C++ language server
    --     "cmake",       -- CMake language server (cmake-language-server)
    --     -- nice-to-have for C++ projects
    --     "bashls",      -- shell scripts in toolchains
    --     "jsonls",      -- compile_commands.json, configs
    --     "yamlls",      -- CI/tooling files
    --   },
    -- })

    -- Debug adapters (DAP)
    mason_dap.setup({
      ensure_installed = {
        "codelldb",    -- great for C/C++
        "cpptools",  -- alternative (optional)
      },
      --automatic_installation = true,
    })

    -- Formatters / Linters / Utilities (non-LSP)
    mason_tools.setup({
      ensure_installed = {
        -- C/C++
        "clang-format",  -- formatter
        "cpplint",       -- optional Google-style linter

        -- CMake
        "cmakelint",     -- lints CMakeLists.txts 
        "cmakelang",     -- formatter (cmake-format)

        -- General helpers you often need in C++ repos
        "codespell",     -- simple spell checker for identifiers/comments
        "shellcheck",    -- bash script linter
        "shfmt",         -- bash formatter
        "jsonlint",      -- json validation (optional)
      },
      auto_update = false,
      run_on_start = true,
    })
  end,
}

