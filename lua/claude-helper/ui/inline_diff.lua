-- Inline diff display using extmarks and signs for claude-helper.nvim
local M = {}

local config = require("claude-helper.config")

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("claude_helper_inline_diff")

-- Track active diff decorations per buffer
local state = {
  decorations = {}, -- {[bufnr] = {extmarks = {...}, signs = {...}}}
}

--- Compute a simple line-based diff between old and new content
---@param old_lines table
---@param new_lines table
---@return table diff List of {type = "add"|"delete"|"change", old_line, new_line, old_text, new_text}
local function compute_diff(old_lines, new_lines)
  local diff = {}

  -- Use vim.diff for a proper diff algorithm
  local old_text = table.concat(old_lines, "\n")
  local new_text = table.concat(new_lines, "\n")

  local diff_result = vim.diff(old_text, new_text, {
    result_type = "indices",
    algorithm = "patience",
  })

  -- diff_result is a list of hunks: {old_start, old_count, new_start, new_count}
  for _, hunk in ipairs(diff_result) do
    local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]

    if old_count == 0 then
      -- Pure addition
      for i = 0, new_count - 1 do
        table.insert(diff, {
          type = "add",
          new_line = new_start + i,
          new_text = new_lines[new_start + i] or "",
        })
      end
    elseif new_count == 0 then
      -- Pure deletion
      for i = 0, old_count - 1 do
        table.insert(diff, {
          type = "delete",
          old_line = old_start + i,
          old_text = old_lines[old_start + i] or "",
          -- Position where deletion occurred (after which line in new file)
          position_after = new_start - 1,
        })
      end
    else
      -- Modification (mix of deletions and additions)
      -- Mark deleted lines
      for i = 0, old_count - 1 do
        table.insert(diff, {
          type = "delete",
          old_line = old_start + i,
          old_text = old_lines[old_start + i] or "",
          position_after = new_start - 1,
        })
      end
      -- Mark added/changed lines
      for i = 0, new_count - 1 do
        table.insert(diff, {
          type = "change",
          new_line = new_start + i,
          new_text = new_lines[new_start + i] or "",
        })
      end
    end
  end

  return diff
end

--- Clear diff decorations for a specific buffer
---@param bufnr number
function M.clear_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Clear signs
  vim.fn.sign_unplace("claude_helper_diff", { buffer = bufnr })

  -- Clear state
  state.decorations[bufnr] = nil
end

--- Clear all diff decorations
function M.clear()
  for bufnr, _ in pairs(state.decorations) do
    M.clear_buffer(bufnr)
  end
  state.decorations = {}
end

--- Show diff for a single buffer
---@param bufnr number
---@param old_lines table Original lines
---@param new_lines table New lines (current buffer content)
function M.show_buffer_diff(bufnr, old_lines, new_lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear existing decorations
  M.clear_buffer(bufnr)

  local cfg = config.get()
  local signs = cfg.inline_diff and cfg.inline_diff.signs or { add = "|", delete = "|", change = "|" }

  -- Compute diff
  local diff = compute_diff(old_lines, new_lines)

  -- Track decorations
  state.decorations[bufnr] = { extmarks = {}, signs = {} }

  -- Group deletions by position for virtual text
  local deletions_by_pos = {}

  for _, entry in ipairs(diff) do
    if entry.type == "delete" then
      local pos = entry.position_after or 0
      deletions_by_pos[pos] = deletions_by_pos[pos] or {}
      table.insert(deletions_by_pos[pos], entry.old_text)
    elseif entry.type == "add" then
      -- Add sign for added line
      local line = entry.new_line
      if line >= 1 and line <= vim.api.nvim_buf_line_count(bufnr) then
        vim.fn.sign_place(0, "claude_helper_diff", "ClaudeHelperDiffAdd", bufnr, { lnum = line })
        table.insert(state.decorations[bufnr].signs, { line = line, type = "add" })

        -- Highlight the line
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "ClaudeHelperDiffAddLine", line - 1, 0, -1)
      end
    elseif entry.type == "change" then
      -- Add sign for changed line
      local line = entry.new_line
      if line >= 1 and line <= vim.api.nvim_buf_line_count(bufnr) then
        vim.fn.sign_place(0, "claude_helper_diff", "ClaudeHelperDiffChange", bufnr, { lnum = line })
        table.insert(state.decorations[bufnr].signs, { line = line, type = "change" })

        -- Highlight the line
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "ClaudeHelperDiffChangeLine", line - 1, 0, -1)
      end
    end
  end

  -- Add virtual text for deleted lines
  for pos, deleted_lines in pairs(deletions_by_pos) do
    local line = math.max(0, pos)
    if line <= vim.api.nvim_buf_line_count(bufnr) then
      -- Create virtual lines for deleted content
      local virt_lines = {}
      for _, text in ipairs(deleted_lines) do
        table.insert(virt_lines, { { "- " .. text, "ClaudeHelperDiffDeleteText" } })
      end

      -- Place virtual text above the line (or at line 0 for deletions at start)
      local extmark_line = line
      if extmark_line > 0 then
        extmark_line = extmark_line - 1
      end

      local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, extmark_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = line > 0,
      })

      table.insert(state.decorations[bufnr].extmarks, extmark_id)

      -- Add sign for deletion
      if line > 0 then
        vim.fn.sign_place(0, "claude_helper_diff", "ClaudeHelperDiffDelete", bufnr, { lnum = line })
      end
    end
  end
end

--- Show diff for all changed files
---@param changes table List of {filepath, old, new, status}
function M.show(changes)
  M.clear()

  for _, change in ipairs(changes) do
    if change.status == "modified" and change.old and change.new then
      -- Find buffer for this file
      local bufnr = nil
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b) == change.filepath then
          bufnr = b
          break
        end
      end

      if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
        local old_lines = vim.split(change.old, "\n", { plain = true })
        local new_lines = vim.split(change.new, "\n", { plain = true })
        M.show_buffer_diff(bufnr, old_lines, new_lines)
      end
    elseif change.status == "added" then
      -- Find buffer for this file
      local bufnr = nil
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b) == change.filepath then
          bufnr = b
          break
        end
      end

      if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
        -- Mark all lines as added
        state.decorations[bufnr] = { extmarks = {}, signs = {} }
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        for line = 1, line_count do
          vim.fn.sign_place(0, "claude_helper_diff", "ClaudeHelperDiffAdd", bufnr, { lnum = line })
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, "ClaudeHelperDiffAddLine", line - 1, 0, -1)
        end
      end
    end
    -- Deleted files don't have a buffer to show diff in
  end
end

--- Check if there are active decorations
---@return boolean
function M.has_decorations()
  return next(state.decorations) ~= nil
end

return M
