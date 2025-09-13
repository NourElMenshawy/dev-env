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
========         ||:lspconfig.lua      ||   |:::::|          ========
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
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
    { "antosha417/nvim-lsp-file-operations", config = true },
    { "folke/neodev.nvim", opts = {} }, -- improves lua_ls for Neovim config
    { "b0o/schemastore.nvim" },
  },
  config = function()
    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    local cmp_nvim_lsp = require("cmp_nvim_lsp")

    -- Buffer-local keymaps on LSP attach
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }
        local map = vim.keymap.set

        opts.desc = "Show LSP references"        ; map("n", "gR", "<cmd>Telescope lsp_references<CR>", opts)
        opts.desc = "Go to declaration"           ; map("n", "gD", vim.lsp.buf.declaration, opts)
        opts.desc = "Show LSP definitions"        ; map("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)
        opts.desc = "Show LSP implementations"    ; map("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts)
        opts.desc = "Show LSP type definitions"   ; map("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts)
        opts.desc = "See code actions"            ; map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        opts.desc = "Smart rename"                ; map("n", "<leader>rn", vim.lsp.buf.rename, opts)
        opts.desc = "Buffer diagnostics"          ; map("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts)
        opts.desc = "Line diagnostics"            ; map("n", "<leader>d", vim.diagnostic.open_float, opts)
        opts.desc = "Prev diagnostic"             ; map("n", "[d", vim.diagnostic.goto_prev, opts)
        opts.desc = "Next diagnostic"             ; map("n", "]d", vim.diagnostic.goto_next, opts)
        opts.desc = "Hover docs"                  ; map("n", "K", vim.lsp.buf.hover, opts)
        opts.desc = "Restart LSP"                 ; map("n", "<leader>rs", ":LspRestart<CR>", opts)
      end,
    })

   --  require("mason-lspconfig").setup({
	  -- ensure_installed = { "clangd", "cmake", "bashls", "jsonls", "yamlls" },
  	--  -- automatic_installation = false,
   --  })
    local servers = { "clangd", "cmake", "bashls", "jsonls", "yamlls", "lua_ls" }
    mason_lspconfig.setup({ ensure_installed = servers })

    -- Capabilities (completion)
    local capabilities = cmp_nvim_lsp.default_capabilities()

    -- Diagnostic signs
    -- local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
    -- for type, icon in pairs(signs) do
    --   local hl = "DiagnosticSign" .. type
    --   vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    -- end
    vim.diagnostic.config({
    signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = " ",
      [vim.diagnostic.severity.WARN]  = " ",
      [vim.diagnostic.severity.HINT]  = "󰠠 ",
      [vim.diagnostic.severity.INFO]  = " ",
      },
     },
   })
    -- Small helpers
    local function setup_default(name)
      if lspconfig[name] then
        lspconfig[name].setup({ capabilities = capabilities })
      end
    end

    local function setup_override(name)
      if name == "clangd" then
        lspconfig.clangd.setup({
          capabilities = capabilities,
          cmd = {
            "clangd",
            "--background-index", "--clang-tidy",
            "--completion-style=detailed", "--header-insertion=iwyu",
          },
        })
        return true
      elseif name == "cmake" then
        lspconfig.cmake.setup({ capabilities = capabilities })
        return true
      elseif name == "lua_ls" then
        lspconfig.lua_ls.setup({
          capabilities = capabilities,
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        })
        return true
      elseif name == "jsonls" then
        local ok, schemastore = pcall(require, "schemastore")
        lspconfig.jsonls.setup({
          capabilities = capabilities,
          settings = ok and {
            json = { schemas = schemastore.json.schemas(), validate = { enable = true } },
          } or nil,
        })
        return true
      elseif name == "yamlls" then
        lspconfig.yamlls.setup({
          capabilities = capabilities,
          settings = {
            yaml = {
              schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
              format = { enable = true },
              validate = true,
            },
          },
        })
        return true
      end
      return false
    end


    -- Configure every server in our list (works on all versions; no setup_handlers)
    for _, name in ipairs(servers) do
      if not setup_override(name) then
        setup_default(name)
      end
    end

   --    require("mason-lspconfig").setup_handlers({
  	-- function(server_name)
   --  	 local ok, server = pcall(function() return lspconfig[server_name] end)
   --  	 if not ok or not server then
   --    		vim.notify("mason-lspconfig: server not found in lspconfig: " .. server_name, vim.log.levels.WARN)
   --    	 return
   --  	end
   --  	server.setup({ capabilities = capabilities })
  	-- end,

      -- ---------- C/C++ (clangd) ----------
--       ["clangd"] = function()
--         lspconfig.clangd.setup({
--           capabilities = capabilities,
--           cmd = {
--             "clangd",
--             "--background-index",
--             "--clang-tidy",
--             "--completion-style=detailed",
--             "--header-insertion=iwyu",
--             "--cross-file-rename",
--           },
--           -- If you ever need it:
--           -- init_options = { clangdFileStatus = true },
--           -- root_dir will auto-detect compile_commands.json / .git
--         })
--       end,
--
--       -- ---------- CMake ----------
--       ["cmake"] = function()
--         lspconfig.cmake.setup({
--           capabilities = capabilities,
--           -- nothing special needed; pairs nicely with compile_commands.json for clangd
--         })
--       end,
--
--       -- ---------- Lua (Neovim config) ----------
--       ["lua_ls"] = function()
--         lspconfig.lua_ls.setup({
--           capabilities = capabilities,
--           settings = {
--             Lua = {
--               diagnostics = { globals = { "vim" } },
--               workspace = { checkThirdParty = false },
--               telemetry = { enable = false },
--             },
--           },
--         })
--       end,
--
--       -- ---------- JSON ----------
--       ["jsonls"] = function()
--         lspconfig.jsonls.setup({
--           capabilities = capabilities,
--           settings = {
--             json = {
--               schemas = require("schemastore").json.schemas(), -- if you install b0o/schemastore.nvim
--               validate = { enable = true },
--             },
--           },
--         })
--       end,
--
--       -- ---------- YAML ----------
--       ["yamlls"] = function()
--         lspconfig.yamlls.setup({
--           capabilities = capabilities,
--           settings = {
--             yaml = {
--               schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
--               format = { enable = true },
--               validate = true,
--             },
--           },
--         })
--       end,
--     })
   end,
 }

