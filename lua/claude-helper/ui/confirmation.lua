-- Confirmation dialog for accepting/rejecting Claude's changes
local M = {}

-- Track current confirmation window state
local state = {
  bufnr = nil,
  winid = nil,
  on_accept = nil,
  on_reject = nil,
}

--- Close the confirmation dialog
local function close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.winid = nil
  state.on_accept = nil
  state.on_reject = nil
end

--- Handle accept action
local function handle_accept()
  local on_accept = state.on_accept
  close()
  if on_accept then
    on_accept()
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

--- Show the confirmation dialog
---@param opts table Options: changes, on_accept, on_reject
function M.show(opts)
  opts = opts or {}

  -- Close existing if open
  close()

  local changes = opts.changes or {}

  -- Build content lines
  local lines = {}
  table.insert(lines, "")

  -- Count files by status
  local modified_count = 0
  local added_count = 0
  local deleted_count = 0

  for _, change in ipairs(changes) do
    if change.status == "modified" then
      modified_count = modified_count + 1
    elseif change.status == "added" then
      added_count = added_count + 1
    elseif change.status == "deleted" then
      deleted_count = deleted_count + 1
    end
  end

  local total = modified_count + added_count + deleted_count
  local file_word = total == 1 and "file" or "files"
  table.insert(lines, "  Claude modified " .. total .. " " .. file_word)
  table.insert(lines, "")

  -- List changed files
  for _, change in ipairs(changes) do
    local prefix = "~"
    if change.status == "added" then
      prefix = "+"
    elseif change.status == "deleted" then
      prefix = "-"
    end
    -- Show relative path if possible
    local display_path = change.filepath
    local cwd = vim.fn.getcwd()
    if display_path:sub(1, #cwd) == cwd then
      display_path = display_path:sub(#cwd + 2)
    end
    table.insert(lines, "  " .. prefix .. " " .. display_path)
  end

  table.insert(lines, "")
  table.insert(lines, "  [a]ccept  [r]eject")
  table.insert(lines, "")

  -- Calculate window dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.max(max_width + 4, 36)
  local height = #lines

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
    title = " Confirm Changes ",
    title_pos = "center",
  })

  -- Window options
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false

  -- Store state
  state.bufnr = bufnr
  state.winid = winid
  state.on_accept = opts.on_accept
  state.on_reject = opts.on_reject

  -- Add highlights for the file list
  local ns_id = vim.api.nvim_create_namespace("claude_helper_confirmation")
  for i, line in ipairs(lines) do
    if line:match("^%s+%+") then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffAdd", i - 1, 0, -1)
    elseif line:match("^%s+%-") then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffDelete", i - 1, 0, -1)
    elseif line:match("^%s+~") then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffChange", i - 1, 0, -1)
    elseif line:match("%[a%]ccept") then
      -- Highlight the action line
      local start_a = line:find("%[a%]")
      local start_r = line:find("%[r%]")
      if start_a then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Question", i - 1, start_a - 1, start_a + 9)
      end
      if start_r then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "WarningMsg", i - 1, start_r - 1, start_r + 8)
      end
    end
  end

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

--- Close the dialog (public API)
function M.close()
  close()
end

--- Check if dialog is open
---@return boolean
function M.is_open()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

return M
