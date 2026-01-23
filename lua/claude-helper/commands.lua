-- User commands and keybindings for claude-helper.nvim
local M = {}

local config = require("claude-helper.config")
local terminal = require("claude-helper.terminal")
local context = require("claude-helper.context")
local headless = require("claude-helper.headless")
local prompt_builder = require("claude-helper.prompt")
local applier = require("claude-helper.applier")
local ui = require("claude-helper.ui")

--- Handle proposal acceptance
---@param proposal table The proposal to apply
local function handle_accept_proposal(proposal)
  -- Apply all changes
  local ok, errors = applier.apply_proposal(proposal)

  if ok then
    -- Reload affected buffers
    applier.reload_buffers(proposal)
    vim.notify("Changes applied successfully", vim.log.levels.INFO)
  else
    local error_msgs = {}
    for _, err in ipairs(errors or {}) do
      table.insert(error_msgs, string.format("Change #%d: %s", err.change_index, err.error))
    end
    vim.notify("Errors applying changes:\n" .. table.concat(error_msgs, "\n"), vim.log.levels.ERROR)
  end
end

--- Handle proposal rejection
local function handle_reject_proposal()
  vim.notify("Changes rejected", vim.log.levels.INFO)
end

--- Handle completion of Claude proposal request
---@param proposal table The parsed proposal
local function on_proposal_complete(proposal)
  -- Hide progress spinner
  ui.progress.hide()

  if not proposal or not proposal.changes or #proposal.changes == 0 then
    vim.notify("Claude completed but proposed no changes", vim.log.levels.INFO)
    return
  end

  -- Show proposal preview window
  ui.proposal.show(proposal, {
    on_accept = handle_accept_proposal,
    on_reject = handle_reject_proposal,
  })
end

--- Handle error from Claude proposal request
---@param err string Error message
local function on_proposal_error(err)
  ui.progress.hide()
  vim.notify("Claude error: " .. (err or "unknown"), vim.log.levels.ERROR)
end

--- Send visual selection to Claude with a prompt (proposal workflow)
---@param opts table|nil Options from command invocation
function M.send_to_claude(opts)
  opts = opts or {}

  -- Get visual selection
  local selection = context.get_visual_selection()
  if not selection then
    vim.notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  -- Open input dialog for prompt
  ui.input.open({
    on_submit = function(user_prompt)
      -- Build the full prompt with system instructions
      local full_prompt = prompt_builder.build_from_selection(selection, user_prompt)

      -- Show progress spinner
      ui.progress.show()

      -- Run Claude in proposal mode
      headless.run_proposal(full_prompt, {
        on_complete = on_proposal_complete,
        on_error = on_proposal_error,
      })
    end,
  })
end

--- Send to Claude using terminal workflow (legacy)
---@param opts table|nil Options from command invocation
function M.send_to_claude_terminal(opts)
  opts = opts or {}

  -- Get visual selection
  local selection = context.get_visual_selection()
  if not selection then
    vim.notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  -- Open input dialog for prompt
  ui.input.open({
    on_submit = function(prompt)
      -- Send to Claude terminal (auto-submits with newline)
      local success = terminal.send_to_claude(selection, prompt)
      if success then
        vim.notify("Sent to Claude", vim.log.levels.INFO)
      end
    end,
  })
end

--- Handle completion of Claude's work (legacy file-watching workflow)
local function on_claude_complete()
  -- Hide progress spinner
  ui.progress.hide()

  -- Detect changes
  local changes = headless.detect_changes()

  if #changes == 0 then
    vim.notify("Claude completed but made no changes", vim.log.levels.INFO)
    return
  end

  -- Reload changed buffers
  headless.reload_changed_buffers()

  -- Show inline diff
  ui.inline_diff.show(changes)

  -- Show confirmation dialog
  ui.confirmation.show({
    changes = changes,
    on_accept = function()
      ui.inline_diff.clear()
      headless.accept_changes()
      vim.notify("Changes accepted", vim.log.levels.INFO)
    end,
    on_reject = function()
      ui.inline_diff.clear()
      local ok, err = headless.revert_changes()
      if ok then
        vim.notify("Changes reverted", vim.log.levels.INFO)
      else
        vim.notify("Error reverting: " .. (err or "unknown"), vim.log.levels.ERROR)
      end
    end,
  })
end

--- Handle error from Claude (legacy)
local function on_claude_error(err)
  ui.progress.hide()
  vim.notify("Claude error: " .. (err or "unknown"), vim.log.levels.ERROR)
end

--- Accept Claude's changes
function M.accept_changes()
  if not ui.inline_diff.has_decorations() then
    vim.notify("No pending changes to accept", vim.log.levels.WARN)
    return
  end

  ui.confirmation.close()
  ui.inline_diff.clear()
  headless.accept_changes()
  vim.notify("Changes accepted", vim.log.levels.INFO)
end

--- Reject Claude's changes
function M.reject_changes()
  if not ui.inline_diff.has_decorations() then
    vim.notify("No pending changes to reject", vim.log.levels.WARN)
    return
  end

  ui.confirmation.close()
  ui.inline_diff.clear()
  local ok, err = headless.revert_changes()
  if ok then
    vim.notify("Changes reverted", vim.log.levels.INFO)
  else
    vim.notify("Error reverting: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end

--- Cancel running Claude job
function M.cancel_claude()
  if not headless.is_running() then
    vim.notify("Claude is not running", vim.log.levels.WARN)
    return
  end

  headless.cancel()
  ui.progress.hide()
  vim.notify("Claude cancelled", vim.log.levels.INFO)
end

--- Show git diff in split buffer
function M.show_diff()
  ui.diff.show()
end

--- Refresh the diff display
function M.refresh_diff()
  if ui.diff.is_open() then
    ui.diff.refresh()
    vim.notify("Diff refreshed", vim.log.levels.INFO)
  else
    vim.notify("Diff window not open", vim.log.levels.WARN)
  end
end

--- Close the diff window
function M.close_diff()
  ui.diff.close()
end

--- Register user commands
function M.register_commands()
  -- Main command to send selection to Claude (proposal workflow)
  vim.api.nvim_create_user_command("ClaudeHelper", function(opts)
    M.send_to_claude(opts)
  end, {
    range = true,
    desc = "Send visual selection to Claude (proposal workflow)",
  })

  -- Legacy terminal workflow command
  vim.api.nvim_create_user_command("ClaudeHelperTerminal", function(opts)
    M.send_to_claude_terminal(opts)
  end, {
    range = true,
    desc = "Send visual selection to Claude terminal (legacy)",
  })

  -- Accept changes command
  vim.api.nvim_create_user_command("ClaudeHelperAccept", function()
    M.accept_changes()
  end, {
    desc = "Accept Claude's changes",
  })

  -- Reject changes command
  vim.api.nvim_create_user_command("ClaudeHelperReject", function()
    M.reject_changes()
  end, {
    desc = "Reject Claude's changes",
  })

  -- Cancel running Claude command
  vim.api.nvim_create_user_command("ClaudeHelperCancel", function()
    M.cancel_claude()
  end, {
    desc = "Cancel running Claude job",
  })

  -- Diff commands
  vim.api.nvim_create_user_command("ClaudeHelperDiff", function()
    M.show_diff()
  end, {
    desc = "Show git diff in split buffer",
  })

  vim.api.nvim_create_user_command("ClaudeHelperDiffRefresh", function()
    M.refresh_diff()
  end, {
    desc = "Refresh the git diff display",
  })

  vim.api.nvim_create_user_command("ClaudeHelperDiffClose", function()
    M.close_diff()
  end, {
    desc = "Close the diff window",
  })
end

--- Register default keybindings
function M.register_keymaps()
  local cfg = config.get()

  -- Visual mode keymap for sending to Claude
  vim.keymap.set("v", cfg.keymaps.send, function()
    -- Exit visual mode first so marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    -- Schedule the command to run after visual mode is exited
    vim.schedule(function()
      M.send_to_claude()
    end)
  end, {
    noremap = true,
    silent = true,
    desc = "Send selection to Claude",
  })

  -- Normal mode keymap for showing diff
  vim.keymap.set("n", cfg.keymaps.show_diff, function()
    M.show_diff()
  end, {
    noremap = true,
    silent = true,
    desc = "Show git diff",
  })

  -- Normal mode keymap for accepting changes
  vim.keymap.set("n", cfg.keymaps.accept, function()
    M.accept_changes()
  end, {
    noremap = true,
    silent = true,
    desc = "Accept Claude's changes",
  })

  -- Normal mode keymap for rejecting changes
  vim.keymap.set("n", cfg.keymaps.reject, function()
    M.reject_changes()
  end, {
    noremap = true,
    silent = true,
    desc = "Reject Claude's changes",
  })

  -- Normal mode keymap for cancelling Claude
  vim.keymap.set("n", cfg.keymaps.cancel, function()
    M.cancel_claude()
  end, {
    noremap = true,
    silent = true,
    desc = "Cancel Claude",
  })
end

return M
