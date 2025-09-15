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
========         ||:cmake.lua          ||   |:::::|          ========
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
  "Civitasv/cmake-tools.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "akinsho/toggleterm.nvim" },
  config = function()
    require("cmake-tools").setup {
      cmake_command = "cmake", -- or "cmake3" if needed
      cmake_build_directory = "build/${variant}", -- e.g. build/Debug or build/Release
      cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=1" },
      cmake_build_options = {},
      cmake_console_size = 10,  -- terminal height
      cmake_console_position = "belowright", -- where build output goes
    }

    -- 🔑 keymaps go here inside config
    local keymap = vim.keymap
    keymap.set("n", "<leader>cg", "<cmd>CMakeGenerate<cr>", { desc = "CMake generate" })
    keymap.set("n", "<leader>cb", "<cmd>CMakeBuild<cr>", { desc = "CMake build" })
    keymap.set("n", "<leader>cr", "<cmd>CMakeRun<cr>", { desc = "CMake run" })
    keymap.set("n", "<leader>ct", "<cmd>CMakeSelectBuildTarget<cr>", { desc = "CMake target" })
  end,
}

