-- Floating input dialog for claude-helper.nvim
local M = {}

local config = require("claude-helper.config")

-- Track current input window state
local state = {
  bufnr = nil,
  winid = nil,
  on_submit = nil,
}

--- Close the input window
local function close_input()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.winid = nil
  state.on_submit = nil
end

--- Submit the input
local function submit_input()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
  local prompt = table.concat(lines, "\n")

  local on_submit = state.on_submit
  close_input()

  if on_submit and prompt ~= "" then
    on_submit(prompt)
  end
end

--- Open the floating input dialog
---@param opts table Options: on_submit(prompt) callback
function M.open(opts)
  opts = opts or {}

  -- Close existing input if open
  close_input()

  local cfg = config.get()
  local width = cfg.input.width
  local height = 1
  local border = cfg.input.border

  -- Calculate window position (centered)
  local ui = vim.api.nvim_list_uis()[1]
  local editor_width = ui and ui.width or vim.o.columns
  local editor_height = ui and ui.height or vim.o.lines

  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- Create buffer for input
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true

  -- Create floating window
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = border,
    title = " Claude Helper - Enter Prompt ",
    title_pos = "center",
  })

  -- Set window options
  vim.wo[winid].wrap = true
  vim.wo[winid].cursorline = false

  -- Store state
  state.bufnr = bufnr
  state.winid = winid
  state.on_submit = opts.on_submit

  -- Set up keymaps for the input buffer
  local keymap_opts = { buffer = bufnr, noremap = true, silent = true }

  -- Submit on Enter
  vim.keymap.set("i", "<CR>", function()
    submit_input()
  end, keymap_opts)

  vim.keymap.set("n", "<CR>", function()
    submit_input()
  end, keymap_opts)

  -- Cancel on Escape
  vim.keymap.set("i", "<Esc>", function()
    close_input()
  end, keymap_opts)

  vim.keymap.set("n", "<Esc>", function()
    close_input()
  end, keymap_opts)

  vim.keymap.set("n", "q", function()
    close_input()
  end, keymap_opts)

  -- Close on leaving window
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = bufnr,
    once = true,
    callback = function()
      close_input()
    end,
  })

  -- Enter insert mode automatically
  vim.cmd("startinsert")
end

--- Close the input dialog (public API)
function M.close()
  close_input()
end

--- Check if input dialog is open
---@return boolean
function M.is_open()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

return M
