-- claude-helper.nvim plugin entry point
-- Load guard to prevent double-loading
if vim.g.loaded_claude_helper then
  return
end
vim.g.loaded_claude_helper = true

-- Neovim version check (0.9+)
if vim.fn.has("nvim-0.9") ~= 1 then
  vim.notify("claude-helper.nvim requires Neovim 0.9+", vim.log.levels.ERROR)
  return
end

-- Define highlight groups for UI elements
local function setup_highlights()
  -- General UI highlights
  vim.api.nvim_set_hl(0, "ClaudeHelperBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "ClaudeHelperTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "ClaudeHelperPrompt", { link = "Normal", default = true })

  -- Progress spinner highlight
  vim.api.nvim_set_hl(0, "ClaudeHelperProgress", { link = "DiagnosticInfo", default = true })

  -- Inline diff highlights
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffAdd", { fg = "#98c379", default = true })
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffDelete", { fg = "#e06c75", default = true })
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffChange", { fg = "#e5c07b", default = true })

  -- Line background highlights for inline diff
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffAddLine", { bg = "#2d3d2d", default = true })
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffChangeLine", { bg = "#3d3d2d", default = true })

  -- Virtual text for deleted lines
  vim.api.nvim_set_hl(0, "ClaudeHelperDiffDeleteText", { fg = "#888888", italic = true, default = true })
end

-- Define signs for inline diff
local function setup_signs()
  vim.fn.sign_define("ClaudeHelperDiffAdd", {
    text = "|",
    texthl = "ClaudeHelperDiffAdd",
    numhl = "",
  })
  vim.fn.sign_define("ClaudeHelperDiffDelete", {
    text = "|",
    texthl = "ClaudeHelperDiffDelete",
    numhl = "",
  })
  vim.fn.sign_define("ClaudeHelperDiffChange", {
    text = "|",
    texthl = "ClaudeHelperDiffChange",
    numhl = "",
  })
end

setup_highlights()
setup_signs()

-- Re-apply highlights on colorscheme change
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ClaudeHelperHighlights", { clear = true }),
  callback = function()
    setup_highlights()
    setup_signs()
  end,
})

-- Track terminal buffers via TermOpen autocmd
vim.g.claude_helper_terminals = vim.g.claude_helper_terminals or {}

vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("ClaudeHelperTerminal", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    vim.g.claude_helper_terminals = vim.g.claude_helper_terminals or {}
    table.insert(vim.g.claude_helper_terminals, bufnr)
  end,
})

-- Clean up closed terminal buffers
vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("ClaudeHelperTerminalCleanup", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local terminals = vim.g.claude_helper_terminals or {}
    local new_terminals = {}
    for _, term_bufnr in ipairs(terminals) do
      if term_bufnr ~= bufnr then
        table.insert(new_terminals, term_bufnr)
      end
    end
    vim.g.claude_helper_terminals = new_terminals
  end,
})
