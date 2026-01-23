-- Visual selection extraction for claude-helper.nvim
local M = {}

--- Get the current visual selection
---@return table|nil selection The selection data, or nil if no selection
function M.get_visual_selection()
  -- Get the start and end positions of the visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local end_line = end_pos[2]

  -- Ensure we have valid line numbers
  if start_line == 0 or end_line == 0 then
    return nil
  end

  -- Get the buffer number
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the selected lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil
  end

  -- Get file information
  local filename = vim.fn.expand("%:t") -- Just the filename
  local filepath = vim.fn.expand("%:p") -- Full path
  local filetype = vim.bo[bufnr].filetype

  return {
    lines = lines,
    start_line = start_line,
    end_line = end_line,
    filetype = filetype,
    filename = filename,
    filepath = filepath,
    bufnr = bufnr,
  }
end

--- Get the current visual selection with column information (for partial line selection)
---@return table|nil selection The selection data with column info
function M.get_visual_selection_with_columns()
  local mode = vim.fn.mode()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line == 0 or end_line == 0 then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil
  end

  -- Handle visual mode selection (trim first and last lines if needed)
  if mode == "v" or mode == "\22" then -- visual or visual-block
    if #lines == 1 then
      lines[1] = lines[1]:sub(start_col, end_col)
    else
      lines[1] = lines[1]:sub(start_col)
      lines[#lines] = lines[#lines]:sub(1, end_col)
    end
  end

  local filename = vim.fn.expand("%:t")
  local filepath = vim.fn.expand("%:p")
  local filetype = vim.bo[bufnr].filetype

  return {
    lines = lines,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
    filetype = filetype,
    filename = filename,
    filepath = filepath,
    bufnr = bufnr,
  }
end

return M
