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
========         ||:dap.lua            ||   |:::::|          ========
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
  -- Core DAP
  {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    dependencies = {
      "rcarriga/nvim-dap-ui",            -- UI panes
      "theHamsta/nvim-dap-virtual-text", -- inline values
      --"jay-babu/mason-nvim-dap.nvim",    -- install adapters via mason
      "nvim-telescope/telescope.nvim",   -- optional: pick configs via Telescope
      "nvim-neotest/nvim-nio",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      -- UI
      dapui.setup()
      require("nvim-dap-virtual-text").setup()

      -- Auto open/close UI
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]      = function() dapui.close() end

      -- Helper: default program picker pointing to build dir
      local function pick_exe(default_name)
        local cwd = vim.fn.getcwd()
        local guess = cwd .. "/build/" .. (default_name or "")
        return vim.fn.input("Executable path: ", guess, "file")
      end

      ----------------------------------------------------------------
      -- Adapters
      ----------------------------------------------------------------
      -- 1) Microsoft cpptools adapter (GDB/LLDB via MI)
      dap.adapters.cppdbg = {
        type = "executable",
        command = vim.fn.stdpath("data") .. "/mason/bin/OpenDebugAD7",
      }

      -- 2) CodeLLDB adapter (pure LLDB)
      local codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = codelldb, args = { "--port", "${port}" } },
      }

      ----------------------------------------------------------------
      -- Configurations (you will choose one at run time)
      ----------------------------------------------------------------
      -- Desktop (GDB)
      local cfg_gdb = {
        name = "Launch (GDB/cpptools)",
        type = "cppdbg",
        request = "launch",
        program = function() return pick_exe("myapp") end,
        cwd = "${workspaceFolder}",
        stopAtEntry = false,
        MIMode = "gdb",
        miDebuggerPath = "/usr/bin/gdb", -- or another gdb in PATH
        setupCommands = {
          { text = "-enable-pretty-printing", ignoreFailures = true },
        },
      }

      -- Desktop (LLDB / codelldb)
      local cfg_lldb = {
        name = "Launch (LLDB/codelldb)",
        type = "codelldb",
        request = "launch",
        program = function() return pick_exe("myapp") end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      }

      -- Embedded: attach to gdbserver (OpenOCD :3333, pyOCD, JLinkGDBServer, etc.)
      local cfg_gdb_attach = {
        name = "Attach GDB to :3333 (embedded)",
        type = "cppdbg",
        request = "launch",
        MIMode = "gdb",
        miDebuggerPath = "/usr/bin/arm-none-eabi-gdb", -- change if needed
        program = function() return pick_exe("firmware.elf") end, -- ELF with symbols
        cwd = "${workspaceFolder}",
        miDebuggerServerAddress = "localhost:3333",
        setupCommands = {
          { text = "-enable-pretty-printing", ignoreFailures = true },
          -- Optional: pre-load, reset, halt (depends on target)
          -- { text = "monitor reset halt" },
          -- { text = "load" },
        },
      }

      -- Apply to C and C++
      dap.configurations.cpp = { cfg_gdb, cfg_lldb, cfg_gdb_attach }
      dap.configurations.c   = dap.configurations.cpp

      ----------------------------------------------------------------
      -- Keymaps (feel IDE-like)
      ----------------------------------------------------------------
      local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true }) end
      map("<F5>",  function() require("dap").continue() end,               "DAP Continue/Start")
      map("<F6>",  function() require("dap").terminate() end,              "DAP Terminate")
      map("<F9>",  function() require("dap").toggle_breakpoint() end,      "DAP Toggle Breakpoint")
      map("<F10>", function() require("dap").step_over() end,              "DAP Step Over")
      map("<F11>", function() require("dap").step_into() end,              "DAP Step Into")
      map("<F12>", function() require("dap").step_out() end,               "DAP Step Out")
      map("<leader>du", function() dapui.toggle() end,                     "DAP UI Toggle")
      map("<leader>dc", function()
        -- Pick a configuration at runtime (works well if you have telescope)
        local ok = pcall(require("telescope").extensions.dap.configurations)
        if ok then require("telescope").extensions.dap.configurations({})
        else print("Install nvim-telescope + telescope-dap (optional)") end
      end, "DAP Pick Configuration")
    end,
  },

  -- Make sure adapters are installed via Mason
--   {
--     "jay-babu/mason-nvim-dap.nvim",
--     dependencies = { "williamboman/mason.nvim" },
--     opts = {
--       ensure_installed = { "cpptools", "codelldb" }, -- both adapters
--       --automatic_installation = true,
--     },
--   },
--
--   -- Optional: Telescope DAP picker (for <leader>dc)
--   {
--     "nvim-telescope/telescope-dap.nvim",
--     dependencies = { "nvim-telescope/telescope.nvim", "mfussenegger/nvim-dap" },
--     config = function() require("telescope").load_extension("dap") end,
--   },
}
