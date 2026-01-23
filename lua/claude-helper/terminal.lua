-- Terminal detection and communication for claude-helper.nvim
local M = {}

local config = require("claude-helper.config")

--- Find a terminal buffer matching the Claude pattern
---@return number|nil bufnr The buffer number of the Claude terminal, or nil if not found
function M.find_claude_terminal()
  local pattern = config.get().terminal.name_pattern

  -- Check all buffers for terminal buftype matching pattern
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname:lower():find(pattern:lower()) then
        return bufnr
      end
    end
  end

  return nil
end

--- Send text to a terminal buffer
---@param bufnr number The terminal buffer number
---@param text string The text to send
---@return boolean success Whether the send was successful
function M.send(bufnr, text)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("Invalid terminal buffer", vim.log.levels.ERROR)
    return false
  end

  local channel = vim.bo[bufnr].channel
  if channel == 0 then
    vim.notify("Terminal channel not found", vim.log.levels.ERROR)
    return false
  end

  -- Send the text to the terminal
  vim.api.nvim_chan_send(channel, text)
  return true
end

--- Format a message with code selection and user prompt
---@param selection table The selection data from context.get_visual_selection()
---@param prompt string The user's prompt
---@return string The formatted message
function M.format_message(selection, prompt)
  local lines = table.concat(selection.lines, "\n")
  local filename = selection.filename or "unknown"
  local filetype = selection.filetype or ""

  local message = string.format(
    [[Here is some code from %s:

```%s
%s
```

%s]],
    filename,
    filetype,
    lines,
    prompt
  )

  return message
end

--- Send a formatted message to the Claude terminal
---@param selection table The selection data
---@param prompt string The user's prompt
---@return boolean success Whether the send was successful
function M.send_to_claude(selection, prompt)
  local bufnr = M.find_claude_terminal()
  if not bufnr then
    vim.notify("Claude terminal not found. Start one with :terminal claude", vim.log.levels.WARN)
    return false
  end

  local message = M.format_message(selection, prompt)

  -- Send the message first
  local success = M.send(bufnr, message)
  if not success then
    return false
  end

  -- Send Enter separately after a short delay to submit
  vim.defer_fn(function()
    M.send(bufnr, "\r")
  end, 50)

  return true
end

--- Format a message for headless Claude execution
--- Includes full file path and working directory so Claude knows exactly what to edit
---@param selection table The selection data from context.get_visual_selection()
---@param prompt string The user's prompt
---@param opts table|nil Additional options
---@return string The formatted prompt for headless execution
function M.format_headless_prompt(selection, prompt, opts)
  opts = opts or {}

  local lines = table.concat(selection.lines, "\n")
  local filepath = selection.filepath or "unknown"
  local filetype = selection.filetype or ""
  local start_line = selection.start_line or 1
  local end_line = selection.end_line or start_line
  local cwd = vim.fn.getcwd()

  local message = string.format(
    [[Working directory: %s

I'm editing the file: %s

Here is the code from lines %d-%d:

```%s
%s
```

%s

Please make the requested changes directly to the file. Do not ask for confirmation.]],
    cwd,
    filepath,
    start_line,
    end_line,
    filetype,
    lines,
    prompt
  )

  return message
end

return M
