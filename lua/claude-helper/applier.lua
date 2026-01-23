-- Applies change proposals to files for claude-helper.nvim
local M = {}

--- Read file contents
---@param filepath string
---@return string|nil content
---@return string|nil error
local function read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. filepath
  end
  local content = file:read("*a")
  file:close()
  return content, nil
end

--- Write content to file
---@param filepath string
---@param content string
---@return boolean success
---@return string|nil error
local function write_file(filepath, content)
  local file = io.open(filepath, "w")
  if not file then
    return false, "Could not write file: " .. filepath
  end
  file:write(content)
  file:close()
  return true, nil
end

--- Get lines from a buffer or file
---@param filepath string
---@return table|nil lines
---@return string|nil error
local function get_file_lines(filepath)
  local content, err = read_file(filepath)
  if not content then
    return nil, err
  end
  return vim.split(content, "\n", { plain = true }), nil
end

--- Validate a single change against current file state
---@param change table The change entry
---@return boolean valid
---@return string|nil error
function M.validate_change(change)
  local lines, err = get_file_lines(change.filepath)
  if not lines then
    return false, err
  end

  local line_count = #lines

  -- Check if line range is valid
  if change.start_line < 1 then
    return false, "start_line must be >= 1"
  end

  if change.end_line > line_count then
    return false, string.format(
      "end_line (%d) exceeds file length (%d)",
      change.end_line,
      line_count
    )
  end

  return true, nil
end

--- Validate all changes in a proposal
---@param proposal table The proposal
---@return boolean valid
---@return table|nil errors List of {change_index, error}
function M.validate_proposal(proposal)
  local errors = {}

  for i, change in ipairs(proposal.changes) do
    local valid, err = M.validate_change(change)
    if not valid then
      table.insert(errors, { change_index = i, error = err })
    end
  end

  if #errors > 0 then
    return false, errors
  end
  return true, nil
end

--- Apply a single change to a file
---@param change table The change entry
---@return boolean success
---@return string|nil error
function M.apply_change(change)
  local lines, err = get_file_lines(change.filepath)
  if not lines then
    return false, err
  end

  -- Split new content into lines
  local new_lines = vim.split(change.new_content, "\n", { plain = true })

  -- Build the new file content
  local result_lines = {}

  -- Add lines before the change
  for i = 1, change.start_line - 1 do
    table.insert(result_lines, lines[i])
  end

  -- Add new content
  for _, line in ipairs(new_lines) do
    table.insert(result_lines, line)
  end

  -- Add lines after the change
  for i = change.end_line + 1, #lines do
    table.insert(result_lines, lines[i])
  end

  -- Write back to file
  local content = table.concat(result_lines, "\n")
  return write_file(change.filepath, content)
end

--- Apply all changes from a proposal
--- Changes are sorted and applied in reverse line order to preserve line numbers
---@param proposal table The proposal
---@return boolean success
---@return table|nil errors List of {change_index, error}
function M.apply_proposal(proposal)
  -- Group changes by file
  local changes_by_file = {}
  for i, change in ipairs(proposal.changes) do
    local filepath = change.filepath
    if not changes_by_file[filepath] then
      changes_by_file[filepath] = {}
    end
    table.insert(changes_by_file[filepath], {
      index = i,
      change = change,
    })
  end

  local errors = {}

  -- Process each file
  for filepath, file_changes in pairs(changes_by_file) do
    -- Sort changes by start_line in descending order
    -- This way we apply from bottom to top, preserving line numbers
    table.sort(file_changes, function(a, b)
      return a.change.start_line > b.change.start_line
    end)

    -- Read file once
    local lines, err = get_file_lines(filepath)
    if not lines then
      for _, fc in ipairs(file_changes) do
        table.insert(errors, { change_index = fc.index, error = err })
      end
      goto continue
    end

    -- Apply each change to the lines array
    for _, fc in ipairs(file_changes) do
      local change = fc.change
      local new_lines = vim.split(change.new_content, "\n", { plain = true })

      -- Validate line range
      if change.start_line < 1 or change.end_line > #lines then
        table.insert(errors, {
          change_index = fc.index,
          error = string.format(
            "Line range %d-%d invalid for file with %d lines",
            change.start_line,
            change.end_line,
            #lines
          ),
        })
        goto next_change
      end

      -- Build new lines array
      local result_lines = {}

      -- Add lines before the change
      for i = 1, change.start_line - 1 do
        table.insert(result_lines, lines[i])
      end

      -- Add new content
      for _, line in ipairs(new_lines) do
        table.insert(result_lines, line)
      end

      -- Add lines after the change
      for i = change.end_line + 1, #lines do
        table.insert(result_lines, lines[i])
      end

      lines = result_lines

      ::next_change::
    end

    -- Write back to file
    local content = table.concat(lines, "\n")
    local ok, write_err = write_file(filepath, content)
    if not ok then
      for _, fc in ipairs(file_changes) do
        table.insert(errors, { change_index = fc.index, error = write_err })
      end
    end

    ::continue::
  end

  if #errors > 0 then
    return false, errors
  end
  return true, nil
end

--- Reload buffers for files that were changed
---@param proposal table The proposal
function M.reload_buffers(proposal)
  -- Collect unique filepaths
  local filepaths = {}
  for _, change in ipairs(proposal.changes) do
    filepaths[change.filepath] = true
  end

  -- Reload each affected buffer
  for filepath, _ in pairs(filepaths) do
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) == filepath then
        if vim.api.nvim_buf_is_loaded(bufnr) then
          if vim.bo[bufnr].modified then
            vim.notify("Buffer has unsaved changes: " .. filepath, vim.log.levels.WARN)
          else
            -- Temporarily enable modifiable if needed for reload
            local was_modifiable = vim.bo[bufnr].modifiable
            if not was_modifiable then
              vim.bo[bufnr].modifiable = true
            end
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("edit!")
            end)
            -- Restore modifiable state if it was off (edit! may have reset it)
            if not was_modifiable and vim.api.nvim_buf_is_valid(bufnr) then
              vim.bo[bufnr].modifiable = false
            end
          end
        end
        break
      end
    end
  end
end

--- Preview what a change would look like (returns diff info)
---@param change table The change entry
---@return table|nil preview {old_lines, new_lines, start_line, end_line}
---@return string|nil error
function M.preview_change(change)
  local lines, err = get_file_lines(change.filepath)
  if not lines then
    return nil, err
  end

  -- Extract old lines
  local old_lines = {}
  for i = change.start_line, change.end_line do
    table.insert(old_lines, lines[i] or "")
  end

  -- Parse new content
  local new_lines = vim.split(change.new_content, "\n", { plain = true })

  return {
    old_lines = old_lines,
    new_lines = new_lines,
    start_line = change.start_line,
    end_line = change.end_line,
    filepath = change.filepath,
  }, nil
end

return M
