-- Progress spinner for claude-helper.nvim
local M = {}

-- Spinner frames
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Track spinner state
local state = {
  bufnr = nil,
  winid = nil,
  timer = nil,
  frame_index = 1,
}

--- Update the spinner frame
local function update_spinner()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  state.frame_index = (state.frame_index % #spinner_frames) + 1
  local frame = spinner_frames[state.frame_index]
  local text = " " .. frame .. " Claude is thinking... "

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { text })
  vim.bo[state.bufnr].modifiable = false
end

--- Show the progress spinner
---@param opts table|nil Options: position ("top-right", "bottom-right", "top-left", "bottom-left")
function M.show(opts)
  opts = opts or {}

  -- Close existing if open
  M.hide()

  local text = " " .. spinner_frames[1] .. " Claude is thinking... "
  local width = vim.fn.strdisplaywidth(text)
  local height = 1

  -- Calculate position (default: top-right)
  local position = opts.position or "top-right"
  local row, col

  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines

  if position == "top-right" then
    row = 1
    col = editor_width - width - 4
  elseif position == "bottom-right" then
    row = editor_height - 4
    col = editor_width - width - 4
  elseif position == "top-left" then
    row = 1
    col = 2
  elseif position == "bottom-left" then
    row = editor_height - 4
    col = 2
  else
    row = 1
    col = editor_width - width - 4
  end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { text })
  vim.bo[bufnr].modifiable = false

  -- Create floating window
  local winid = vim.api.nvim_open_win(bufnr, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })

  -- Window options
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false

  -- Add highlight
  local ns_id = vim.api.nvim_create_namespace("claude_helper_progress")
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "ClaudeHelperProgress", 0, 0, -1)

  -- Store state
  state.bufnr = bufnr
  state.winid = winid
  state.frame_index = 1

  -- Start animation timer
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 80, vim.schedule_wrap(function()
    update_spinner()
  end))
end

--- Hide the progress spinner
function M.hide()
  -- Stop timer
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  -- Close window
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end

  -- Delete buffer
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end

  state.bufnr = nil
  state.winid = nil
end

--- Check if spinner is visible
---@return boolean
function M.is_visible()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

return M
