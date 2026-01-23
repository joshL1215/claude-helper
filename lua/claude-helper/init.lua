-- claude-helper.nvim - Send code to Claude Code in Neovim terminal
-- Main module with setup() and public API

local M = {}

local config = require("claude-helper.config")
local commands = require("claude-helper.commands")
local terminal = require("claude-helper.terminal")
local context = require("claude-helper.context")
local headless = require("claude-helper.headless")
local ui = require("claude-helper.ui")
local schema = require("claude-helper.schema")
local prompt = require("claude-helper.prompt")
local applier = require("claude-helper.applier")

--- Setup the plugin with user configuration
---@param opts table|nil User configuration options
function M.setup(opts)
  -- Merge configuration
  config.setup(opts)

  -- Register commands
  commands.register_commands()

  -- Register default keymaps
  commands.register_keymaps()
end

--- Send visual selection to Claude (proposal workflow)
--- Gets selection -> shows input -> runs Claude headless -> shows proposal preview -> confirms
function M.send_to_claude()
  commands.send_to_claude()
end

--- Send visual selection to Claude terminal (legacy workflow)
function M.send_to_claude_terminal()
  commands.send_to_claude_terminal()
end

--- Accept Claude's pending changes
function M.accept_changes()
  commands.accept_changes()
end

--- Reject Claude's pending changes and revert
function M.reject_changes()
  commands.reject_changes()
end

--- Cancel a running Claude job
function M.cancel_claude()
  commands.cancel_claude()
end

--- Check if Claude is currently running
---@return boolean
function M.is_running()
  return headless.is_running()
end

--- Show git diff in a split buffer
function M.show_diff()
  ui.diff.show()
end

--- Refresh the diff display
function M.refresh_diff()
  ui.diff.refresh()
end

--- Close the diff window
function M.close_diff()
  ui.diff.close()
end

--- Find the Claude terminal buffer
---@return number|nil bufnr The terminal buffer number
function M.find_terminal()
  return terminal.find_claude_terminal()
end

--- Get current configuration
---@return table
function M.get_config()
  return config.get()
end

-- Expose submodules for advanced usage
M.terminal = terminal
M.context = context
M.headless = headless
M.ui = ui
M.config = config
M.schema = schema
M.prompt = prompt
M.applier = applier

return M
