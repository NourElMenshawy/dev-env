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

	event = {
		"BufReadPre",
		"BufNewFile",
	},

	dependencies = {
		-- Installs LSP servers through Mason and maps Mason package names
		-- to Neovim LSP configuration names.
		"williamboman/mason-lspconfig.nvim",

		-- Adds nvim-cmp completion capabilities to LSP clients.
		"hrsh7th/cmp-nvim-lsp",

		-- Updates imports/references when files are renamed or moved.
		{
			"antosha417/nvim-lsp-file-operations",
			config = true,
		},

		-- JSON and YAML schema collection.
		{
			"b0o/schemastore.nvim",
		},
	},

	config = function()
		local mason_lspconfig = require("mason-lspconfig")
		local cmp_nvim_lsp = require("cmp_nvim_lsp")

		-- ================================================================
		-- Completion capabilities
		-- ================================================================

		local capabilities = cmp_nvim_lsp.default_capabilities()

		-- Prefer UTF-16 because all enabled LSP clients support it and it
		-- avoids mixed position-encoding warnings.
		capabilities.general = capabilities.general or {}
		capabilities.general.positionEncodings = {
			"utf-16",
		}

		-- ================================================================
		-- Buffer-local keymaps
		-- ================================================================

		local lsp_group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true })

		vim.api.nvim_create_autocmd("LspAttach", {
			group = lsp_group,

			callback = function(event)
				local buffer = event.buf
				local map = vim.keymap.set

				local function opts(description)
					return {
						buffer = buffer,
						silent = true,
						desc = description,
					}
				end

				map("n", "gR", "<cmd>Telescope lsp_references<CR>", opts("Show LSP references"))

				map("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))

				map("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts("Show LSP definitions"))

				map("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts("Show LSP implementations"))

				map("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts("Show LSP type definitions"))

				map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("See code actions"))

				map("n", "<leader>rn", vim.lsp.buf.rename, opts("Smart rename"))

				map("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts("Buffer diagnostics"))

				map("n", "<leader>d", vim.diagnostic.open_float, opts("Line diagnostics"))

				map("n", "[d", function()
					vim.diagnostic.jump({
						count = -1,
						float = true,
					})
				end, opts("Previous diagnostic"))

				map("n", "]d", function()
					vim.diagnostic.jump({
						count = 1,
						float = true,
					})
				end, opts("Next diagnostic"))

				map("n", "K", vim.lsp.buf.hover, opts("Hover documentation"))

				map("n", "<leader>rs", "<cmd>LspRestart<CR>", opts("Restart LSP"))

				map("n", "<leader>li", "<cmd>LspInfo<CR>", opts("Show LSP information"))

				map("n", "<leader>lf", function()
					vim.lsp.buf.format({
						async = true,
					})
				end, opts("Format with LSP"))
			end,
		})

		-- ================================================================
		-- Diagnostics
		-- ================================================================

		vim.diagnostic.config({
			virtual_text = {
				spacing = 4,
				source = "if_many",
				prefix = "●",
			},

			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = " ",
					[vim.diagnostic.severity.WARN] = " ",
					[vim.diagnostic.severity.HINT] = "󰠠 ",
					[vim.diagnostic.severity.INFO] = " ",
				},
			},

			underline = true,
			update_in_insert = false,
			severity_sort = true,

			float = {
				border = "rounded",
				source = true,
				header = "",
				prefix = "",
			},
		})

		-- Rounded borders for hover and signature windows.
		local original_hover = vim.lsp.buf.hover
		vim.lsp.buf.hover = function()
			return original_hover({
				border = "rounded",
			})
		end

		local original_signature_help = vim.lsp.buf.signature_help
		vim.lsp.buf.signature_help = function()
			return original_signature_help({
				border = "rounded",
			})
		end

		-- ================================================================
		-- Mason
		-- ================================================================

		local servers = {
			"clangd",
			"cmake",
			"bashls",
			"jsonls",
			"yamlls",
			"lua_ls",
			"pyright",
			"ruff",
		}

		mason_lspconfig.setup({
			ensure_installed = servers,

			-- Important:
			--
			-- Mason must install the servers, but it must not enable them
			-- automatically. We configure and enable each server exactly
			-- once below.
			automatic_enable = false,
		})

		-- ================================================================
		-- C and C++: clangd
		-- ================================================================

		vim.lsp.config("clangd", {
			capabilities = capabilities,

			cmd = {
				"clangd",

				-- Build a persistent project-wide symbol index.
				"--background-index",

				-- Run clang-tidy diagnostics and code actions.
				"--clang-tidy",

				-- More informative nvim-cmp entries.
				"--completion-style=detailed",

				-- Add missing include directives when accepting completion.
				"--header-insertion=iwyu",

				-- Show the currently parsed file in LSP status information.
				-- "--clangd-tidy-checks=-*,bugprone-*,performance-*,modernize-*",

				-- Your ROS compilation database uses /usr/bin/c++.
				-- This lets clangd query GCC for:
				--   - C++ standard-library headers
				--   - target architecture
				--   - system include paths
				"--query-driver=/usr/bin/c++,/usr/bin/g++,/usr/bin/gcc,/usr/bin/cc,/usr/bin/x86_64-linux-gnu-g++-*",
			},

			filetypes = {
				"c",
				"cpp",
				"objc",
				"objcpp",
				"cuda",
			},

			-- First matching marker determines the project root.
			--
			-- For your ROS workspace, the merged file should be:
			--
			--   ~/workspace/px4_ros_wc/compile_commands.json
			root_markers = {
				"compile_commands.json",
				"compile_flags.txt",
				".clangd",
				".git",
			},

			init_options = {
				clangdFileStatus = true,

				-- Use the workspace-level compilation database that your
				-- ROS plugin generates after successful colcon builds.
				compilationDatabasePath = "",
			},
		})

		-- ================================================================
		-- CMake
		-- ================================================================

		vim.lsp.config("cmake", {
			capabilities = capabilities,

			init_options = {
				buildDirectory = "build",
			},

			root_markers = {
				"CMakePresets.json",
				"CMakeLists.txt",
				"CTestConfig.cmake",
				".git",
			},
		})

		-- ================================================================
		-- Bash
		-- ================================================================

		vim.lsp.config("bashls", {
			capabilities = capabilities,

			settings = {
				bashIde = {
					globPattern = "*@(.sh|.inc|.bash|.command)",
				},
			},

			root_markers = {
				".git",
			},
		})

		-- ================================================================
		-- Lua
		-- ================================================================

		vim.lsp.config("lua_ls", {
			capabilities = capabilities,

			settings = {
				Lua = {
					runtime = {
						version = "LuaJIT",
					},

					diagnostics = {
						globals = {
							"vim",
						},
					},

					workspace = {
						checkThirdParty = false,

						library = {
							vim.env.VIMRUNTIME,
							vim.fn.stdpath("config"),
						},
					},

					completion = {
						callSnippet = "Replace",
					},

					telemetry = {
						enable = false,
					},
				},
			},

			root_markers = {
				".luarc.json",
				".luarc.jsonc",
				".luacheckrc",
				".stylua.toml",
				"stylua.toml",
				"selene.toml",
				"selene.yml",
				".git",
			},
		})

		-- ================================================================
		-- JSON
		-- ================================================================

		local schemastore_ok, schemastore = pcall(require, "schemastore")

		vim.lsp.config("jsonls", {
			capabilities = capabilities,

			settings = {
				json = {
					schemas = schemastore_ok and schemastore.json.schemas() or {},

					validate = {
						enable = true,
					},
				},
			},

			init_options = {
				provideFormatter = true,
			},

			root_markers = {
				".git",
			},
		})

		-- ================================================================
		-- YAML
		-- ================================================================

		vim.lsp.config("yamlls", {
			capabilities = capabilities,

			settings = {
				redhat = {
					telemetry = {
						enabled = false,
					},
				},

				yaml = {
					format = {
						enable = true,
					},

					validate = true,
					hover = true,
					completion = true,

					-- Disable the server's built-in remote schema-store
					-- download because schemastore.nvim provides schemas.
					schemaStore = {
						enable = false,
						url = "",
					},

					schemas = schemastore_ok and schemastore.yaml.schemas() or {},
				},
			},

			root_markers = {
				".git",
			},
		})

		-- ================================================================
		-- Python: Pyright
		-- ================================================================

		vim.lsp.config("pyright", {
			capabilities = capabilities,

			settings = {
				python = {
					analysis = {
						typeCheckingMode = "standard",
						autoImportCompletions = true,
						useLibraryCodeForTypes = true,

						-- Analyze all project files rather than only opened
						-- files.
						diagnosticMode = "workspace",

						autoSearchPaths = true,
					},
				},
			},

			root_markers = {
				"pyproject.toml",
				"poetry.lock",
				"Pipfile",
				"requirements.txt",
				"setup.cfg",
				"setup.py",
				"pyrightconfig.json",
				".git",
			},
		})

		-- ================================================================
		-- Python: Ruff
		-- ================================================================

		vim.lsp.config("ruff", {
			capabilities = capabilities,

			on_attach = function(client)
				-- Pyright provides richer Python hover information.
				-- Disable Ruff's hover implementation to prevent duplicate
				-- or conflicting hover windows.
				client.server_capabilities.hoverProvider = false
			end,

			init_options = {
				settings = {
					args = {},
				},
			},

			root_markers = {
				"pyproject.toml",
				"ruff.toml",
				".ruff.toml",
				".git",
			},
		})

		-- ================================================================
		-- Enable each LSP configuration exactly once
		-- ================================================================

		vim.lsp.enable(servers)
	end,
}
