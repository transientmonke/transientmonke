-- 1. Initialize Global AI State
-- We set this at the top so ALL plugins can read it as the default
vim.env.ANTHROPIC_MODEL = "claude-3-7-sonnet-20250219"
local key = vim.fn.system("~/.anthropic_api_key"):gsub("%s+", "")
vim.env.ANTHROPIC_API_KEY = key

-- Define models table once globally (outside the function)
local ai_models = {
    { name = "Claude 3.7 Sonnet (Thinking)", id = "claude-3-7-sonnet-20250219" },
    { name = "Claude 3.5 Sonnet (Feature/Fast)", id = "claude-3-5-sonnet-20241022" },
    { name = "Claude 3.5 Haiku (Cheap/Small)", id = "claude-3-5-haiku-20241022" },
}

-- 2. Editor Settings
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.termguicolors = true

-- 3. Bootstrap Lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({"git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath})
end
vim.opt.rtp:prepend(lazypath)

-- 4. Plugin Setup
require("lazy").setup({
    {
        'sainnhe/gruvbox-material',
        lazy = false,
        priority = 1000,
        config = function()
          -- Optionally configure and load the colorscheme
          -- 'hard', 'medium' (default), or 'soft'
          vim.g.gruvbox_material_background = 'soft'
          vim.g.gruvbox_material_foreground = 'material'
          vim.cmd.colorscheme('gruvbox-material')
        end,
    },
    { 
        'nvim-telescope/telescope.nvim', 
        tag = '0.1.8', 
        dependencies = { 
            'nvim-lua/plenary.nvim', 
            { 
                'nvim-telescope/telescope-fzf-native.nvim', 
                build = 'make' 
            }
        }, 
        config = function() 
            require('telescope').load_extension('fzf') 
        end 
    },
    {
        'neovim/nvim-lspconfig',
        config = function()
            vim.lsp.config('clangd', {
                capabilities = {
                    offsetEncoding = { "utf-8"  },
                },
                cmd = {
                    "clangd",
                    "--background-index",
                    "--clang-tidy",
                    "--completion-style=detailed",
                },
                initialization_options = {
                    fallbackFlags = {
                        "-Wall",
                        "-Werror",
                        "-Wextra",
                        "-std=c99",
                        "-Wpointer-arith",
                        "-Wfloat-equal",
                        "-Wwrite-strings",
                        "-Waggregate-return",
                        "-Wswitch-default",
                        "-Wswitch-enum",
                        "-Wunreachable-code",
                        "-Wpedantic",
                        "-Wconversion",
                        "-Wshadow",
                        "-Wundef",
                        "-Wcast-align",
                        "-Wformat=2",
                        "-Wstrict-prototypes",
                        "-Wmissing-prototypes",
                        "-fsanitize=address",
                        "-fsanitize=undefined",
                    },
                },
            })
            vim.lsp.enable('clangd')
            vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = "Show code actions" })
            vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = "Go to Definition" })
            vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { desc = "Go to Declaration" })
            vim.keymap.set('n', 'gs', '<cmd>ClangdSwitchSourceHeader<cr>', { desc = "Switch Source/Header" })
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, { desc = "Hover Documentation" })
            vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = "Rename Symbol" })
        end
    },
    {
      "carlos-algms/agentic.nvim",
      dependencies = { "nvim-lua/plenary.nvim", "stevearc/dressing.nvim", "nvim-tree/nvim-web-devicons" },
      config = function()
        -- The Model Selector Function
        local function select_ai_model()
            vim.ui.select(ai_models, {
                prompt = "Select AI Model:",
                format_item = function(item) return item.name end,
            }, function(choice)
                if choice then
                    -- This updates the shell environment for the ACP process
                    vim.env.ANTHROPIC_MODEL = choice.id
                    
                    -- This force-updates Avante if it's installed
                    local avante_ok, avante = pcall(require, "avante.config")
                    if avante_ok then avante.claude.model = choice.id end

                    -- This updates Agentic's internal command environment
                    require("agentic").setup({
                        acp_providers = {
                            ["claude-acp"] = { env = { ANTHROPIC_MODEL = choice.id } }
                        }
                    })
                    vim.notify("Brain swapped: " .. choice.name .. ". Start a NEW session (<leader>gc) to apply.", vim.log.levels.WARN)
                end
            end)
        end

        vim.keymap.set("n", "<leader>gm", select_ai_model, { desc = "AI: Switch Model" })

        -- Single consolidated setup call
        require("agentic").setup({
            provider = "claude-acp",
            diff = { style = "split", auto_preview = true },
            acp_providers = {
                ["claude-acp"] = { 
                    env = { 
                        ANTHROPIC_MODEL = vim.env.ANTHROPIC_MODEL,
                        ANTHROPIC_BETA = "prompt-caching-2024-07-31" -- Added caching!
                    } 
                }
            }
        })
      end,
      keys = {
        { "<leader>ga", function() require("agentic").toggle() end, desc = "Open Agentic Chat" },
        { "<leader>gc", function() 
            require("agentic").new_session() 
            vim.notify("Context Cleared (New Session)", vim.log.levels.INFO)
        end, desc = "Agentic: New Session" },
      }
    },
})

vim.diagnostic.config({
    virtual_text = {
        prefix = '●', -- Could be '■', '▎', 'x'
        spacing = 4,
    },
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
})

-- 5. Global Keymaps
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = "Find Files" })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = "Grep Project" })

-- Autocmd for Agentic FileType
vim.api.nvim_create_autocmd("FileType", {
  pattern = "agentic",
  callback = function()
    vim.keymap.set("n", "d", function() require("agentic.hunks").toggle_diff() end, { buffer = true })
    vim.keymap.set("n", "<leader>go", function() require("agentic.hunks").preview_hunk() end, { buffer = true })
  end,
})
