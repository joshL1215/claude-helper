-- Configuration defaults for claude-helper.nvim
local M = {}

M.defaults = {
  terminal = {
    name_pattern = "claude", -- pattern to find Claude terminal
  },
  input = {
    width = 60,
    border = "rounded",
  },
  diff = {
    split = "vertical",
    position = "right",
    auto_refresh = true,
    debounce_ms = 500,
  },
  headless = {
    claude_path = "claude",
    timeout_ms = 300000, -- 5 min
  },
  proposal = {
    preview_width = 80, -- width of proposal preview window
    preview_height = 30, -- max height of proposal preview window
  },
  inline_diff = {
    signs = { add = "|", delete = "|", change = "|" },
  },
  keymaps = {
    send = "<leader>cc",
    show_diff = "<leader>cd",
    accept = "<leader>ca",
    reject = "<leader>cr",
    cancel = "<leader>cx",
  },
}

-- Current configuration (will be populated by setup)
M.options = vim.deepcopy(M.defaults)

--- Merge user configuration with defaults
---@param opts table|nil User configuration
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

--- Get current configuration
---@return table
function M.get()
  return M.options
end

return M
