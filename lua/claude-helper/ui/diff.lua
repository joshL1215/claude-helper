-- Diff display in split buffer for claude-helper.nvim
local M = {}

local config = require("claude-helper.config")

-- Track diff window state
local state = {
  bufnr = nil,
  winid = nil,
  watcher = nil,
  debounce_timer = nil,
}

--- Get the git diff output
---@return string|nil diff_text The git diff output, or nil on error
local function get_git_diff()
  local result = vim.fn.systemlist("git diff")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return table.concat(result, "\n")
end

--- Update the diff buffer content
local function update_diff_buffer()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local diff_text = get_git_diff()
  if not diff_text then
    diff_text = "-- No changes or not a git repository --"
  elseif diff_text == "" then
    diff_text = "-- No uncommitted changes --"
  end

  -- Make buffer modifiable temporarily
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(diff_text, "\n"))
  vim.bo[state.bufnr].modifiable = false
  vim.bo[state.bufnr].modified = false
end

--- Stop the file watcher
function M.stop_watching()
  if state.watcher then
    state.watcher:stop()
    state.watcher = nil
  end
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer = nil
  end
end

--- Start watching for file changes
---@param dir string|nil Directory to watch (defaults to cwd)
function M.start_watching(dir)
  M.stop_watching()

  local cfg = config.get()
  if not cfg.diff.auto_refresh then
    return
  end

  dir = dir or vim.fn.getcwd()
  local debounce_ms = cfg.diff.debounce_ms

  state.watcher = vim.uv.new_fs_event()
  if not state.watcher then
    return
  end

  state.debounce_timer = vim.uv.new_timer()

  local function on_change(err, filename, events)
    if err then
      return
    end

    -- Skip .git directory changes (too noisy)
    if filename and filename:match("^%.git") then
      return
    end

    -- Debounce: reset timer on each change
    if state.debounce_timer then
      state.debounce_timer:stop()
      state.debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
        M.refresh()
      end))
    end
  end

  -- Watch the directory recursively
  state.watcher:start(dir, { recursive = true }, on_change)
end

--- Close the diff window
function M.close()
  M.stop_watching()

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end

  state.bufnr = nil
  state.winid = nil
end

--- Refresh the diff display
function M.refresh()
  update_diff_buffer()
end

--- Show the diff in a split buffer
---@param diff_text string|nil Optional diff text (will run git diff if not provided)
function M.show(diff_text)
  local cfg = config.get()

  -- If already open, just refresh
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    M.refresh()
    vim.api.nvim_set_current_win(state.winid)
    return
  end

  -- Create buffer for diff
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "diff"

  state.bufnr = bufnr

  -- Create split window
  local split_cmd
  if cfg.diff.split == "vertical" then
    if cfg.diff.position == "right" then
      split_cmd = "botright vsplit"
    else
      split_cmd = "topleft vsplit"
    end
  else
    if cfg.diff.position == "bottom" then
      split_cmd = "botright split"
    else
      split_cmd = "topleft split"
    end
  end

  vim.cmd(split_cmd)
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  state.winid = winid

  -- Set window options
  vim.wo[winid].wrap = false
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].cursorline = true

  -- Set buffer name
  vim.api.nvim_buf_set_name(bufnr, "Claude Helper - Git Diff")

  -- Populate with diff content
  if diff_text then
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(diff_text, "\n"))
    vim.bo[bufnr].modifiable = false
  else
    update_diff_buffer()
  end

  -- Set up keymaps for diff buffer
  local keymap_opts = { buffer = bufnr, noremap = true, silent = true }

  -- Close with q
  vim.keymap.set("n", "q", function()
    M.close()
  end, keymap_opts)

  -- Refresh with r
  vim.keymap.set("n", "r", function()
    M.refresh()
    vim.notify("Diff refreshed", vim.log.levels.INFO)
  end, keymap_opts)

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      M.stop_watching()
      state.bufnr = nil
      state.winid = nil
    end,
  })

  -- Start watching for changes
  M.start_watching()
end

--- Check if diff window is open
---@return boolean
function M.is_open()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

--- Get the diff buffer number
---@return number|nil
function M.get_bufnr()
  return state.bufnr
end

return M
