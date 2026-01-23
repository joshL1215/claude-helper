-- Proposal preview UI for claude-helper.nvim
-- Shows proposed changes with diff visualization and accept/reject keybindings
local M = {}

local applier = require("claude-helper.applier")

-- Namespace for highlights
local ns_id = vim.api.nvim_create_namespace("claude_helper_proposal")

-- Track state
local state = {
  bufnr = nil,
  winid = nil,
  proposal = nil,
  on_accept = nil,
  on_reject = nil,
  current_change_idx = 1,
}

--- Get display path (relative to cwd if possible)
---@param filepath string
---@return string
local function get_display_path(filepath)
  local cwd = vim.fn.getcwd()
  if filepath:sub(1, #cwd) == cwd then
    return filepath:sub(#cwd + 2)
  end
  return filepath
end

--- Build the proposal preview content
---@param proposal table
---@return table lines
---@return table highlights {line, hl_group, col_start, col_end}
local function build_content(proposal)
  local lines = {}
  local highlights = {}

  -- Summary header
  table.insert(lines, "")
  if proposal.summary and proposal.summary ~= "" then
    table.insert(lines, "  Summary: " .. proposal.summary)
  else
    table.insert(lines, "  Proposed Changes")
  end
  table.insert(lines, "")
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  -- List each change with diff preview
  for i, change in ipairs(proposal.changes) do
    local display_path = get_display_path(change.filepath)
    local header = string.format(
      "  [%d/%d] %s (lines %d-%d)",
      i,
      #proposal.changes,
      display_path,
      change.start_line,
      change.end_line
    )
    table.insert(lines, header)
    table.insert(highlights, { line = #lines, hl_group = "Title", col_start = 0, col_end = -1 })

    -- Explanation if present
    if change.explanation and change.explanation ~= "" then
      table.insert(lines, "  " .. change.explanation)
      table.insert(highlights, { line = #lines, hl_group = "Comment", col_start = 0, col_end = -1 })
    end

    table.insert(lines, "")

    -- Get diff preview
    local preview, err = applier.preview_change(change)
    if preview then
      -- Show old lines (deleted)
      if #preview.old_lines > 0 then
        for _, old_line in ipairs(preview.old_lines) do
          table.insert(lines, "  - " .. old_line)
          table.insert(highlights, { line = #lines, hl_group = "DiffDelete", col_start = 0, col_end = -1 })
        end
      end

      -- Show new lines (added)
      if #preview.new_lines > 0 and not (preview.new_lines[1] == "" and #preview.new_lines == 1 and change.new_content == "") then
        for _, new_line in ipairs(preview.new_lines) do
          table.insert(lines, "  + " .. new_line)
          table.insert(highlights, { line = #lines, hl_group = "DiffAdd", col_start = 0, col_end = -1 })
        end
      elseif change.new_content == "" then
        table.insert(lines, "  (lines deleted)")
        table.insert(highlights, { line = #lines, hl_group = "Comment", col_start = 0, col_end = -1 })
      end
    else
      table.insert(lines, "  Error: " .. (err or "unknown"))
      table.insert(highlights, { line = #lines, hl_group = "ErrorMsg", col_start = 0, col_end = -1 })
    end

    table.insert(lines, "")
    if i < #proposal.changes then
      table.insert(lines, string.rep("─", 60))
      table.insert(lines, "")
    end
  end

  -- Footer with keybindings
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")
  table.insert(lines, "  [a]ccept all  [r]eject all  [j/k] navigate  [q] close")
  table.insert(lines, "")

  return lines, highlights
end

--- Close the proposal window
local function close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.winid = nil
  state.proposal = nil
  state.on_accept = nil
  state.on_reject = nil
  state.current_change_idx = 1
end

--- Handle accept action
local function handle_accept()
  local on_accept = state.on_accept
  local proposal = state.proposal
  close()
  if on_accept then
    on_accept(proposal)
  end
end

--- Handle reject action
local function handle_reject()
  local on_reject = state.on_reject
  close()
  if on_reject then
    on_reject()
  end
end

--- Navigate to next change (scroll down)
local function next_change()
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    return
  end
  vim.api.nvim_win_call(state.winid, function()
    vim.cmd("normal! 10j")
  end)
end

--- Navigate to previous change (scroll up)
local function prev_change()
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    return
  end
  vim.api.nvim_win_call(state.winid, function()
    vim.cmd("normal! 10k")
  end)
end

--- Show the proposal preview window
---@param proposal table The proposal to display
---@param opts table Options: on_accept(proposal), on_reject()
function M.show(proposal, opts)
  opts = opts or {}

  -- Close existing if open
  close()

  state.proposal = proposal
  state.on_accept = opts.on_accept
  state.on_reject = opts.on_reject
  state.current_change_idx = 1

  -- Build content
  local lines, highlights = build_content(proposal)

  -- Calculate window dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.min(math.max(max_width + 4, 60), vim.o.columns - 10)
  local height = math.min(#lines, vim.o.lines - 10)

  -- Calculate window position (centered)
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines

  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "claude-proposal"

  -- Set content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Create floating window
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Proposed Changes ",
    title_pos = "center",
  })

  -- Window options
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
  vim.wo[winid].scrolloff = 3

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl.hl_group, hl.line - 1, hl.col_start, hl.col_end)
  end

  -- Store state
  state.bufnr = bufnr
  state.winid = winid

  -- Set up keymaps
  local keymap_opts = { buffer = bufnr, noremap = true, silent = true }

  vim.keymap.set("n", "a", handle_accept, keymap_opts)
  vim.keymap.set("n", "A", handle_accept, keymap_opts)
  vim.keymap.set("n", "y", handle_accept, keymap_opts)
  vim.keymap.set("n", "Y", handle_accept, keymap_opts)
  vim.keymap.set("n", "<CR>", handle_accept, keymap_opts)

  vim.keymap.set("n", "r", handle_reject, keymap_opts)
  vim.keymap.set("n", "R", handle_reject, keymap_opts)
  vim.keymap.set("n", "n", handle_reject, keymap_opts)
  vim.keymap.set("n", "N", handle_reject, keymap_opts)

  vim.keymap.set("n", "<Esc>", handle_reject, keymap_opts)
  vim.keymap.set("n", "q", handle_reject, keymap_opts)

  vim.keymap.set("n", "j", next_change, keymap_opts)
  vim.keymap.set("n", "k", prev_change, keymap_opts)

  -- Standard navigation
  vim.keymap.set("n", "<C-d>", "<C-d>", keymap_opts)
  vim.keymap.set("n", "<C-u>", "<C-u>", keymap_opts)
  vim.keymap.set("n", "G", "G", keymap_opts)
  vim.keymap.set("n", "gg", "gg", keymap_opts)

  -- Close on leaving window
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(function()
        -- Only close if neither accept nor reject was triggered
        if state.winid then
          handle_reject()
        end
      end)
    end,
  })
end

--- Close the proposal window (public API)
function M.close()
  close()
end

--- Check if proposal window is open
---@return boolean
function M.is_open()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

--- Get current proposal
---@return table|nil
function M.get_proposal()
  return state.proposal
end

return M
