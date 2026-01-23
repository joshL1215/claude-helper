-- Prompt construction for claude-helper.nvim
-- Builds prompts that instruct Claude to output structured change proposals
local M = {}

-- System prompt that instructs Claude to output JSON proposals
M.system_instructions = [[You are a code modification assistant. You MUST output ONLY valid JSON describing proposed changes.

CRITICAL: Output ONLY the JSON object, no explanation before or after.

JSON Format:
{
  "summary": "Brief description of what the changes accomplish",
  "changes": [
    {
      "filepath": "/absolute/path/to/file",
      "start_line": <first line number to replace>,
      "end_line": <last line number to replace>,
      "new_content": "the replacement code (can be multiple lines)",
      "explanation": "why this specific change is needed"
    }
  ]
}

Rules:
- Line numbers are 1-indexed
- start_line and end_line define the range of lines to REPLACE (inclusive)
- new_content replaces lines start_line through end_line
- To INSERT code without replacing: set start_line and end_line to the same line, include that original line plus new code in new_content
- To DELETE code: set new_content to empty string ""
- Use actual newlines in new_content, not \n escape sequences
- Preserve correct indentation in new_content
- filepath must be the absolute path provided to you
- Each change should be atomic and focused]]

--- Build a prompt with file context and user request
---@param opts table Options: filepath, filetype, code, start_line, end_line, user_prompt, cwd
---@return string prompt
function M.build(opts)
  local parts = {}

  -- Add system instructions
  table.insert(parts, M.system_instructions)
  table.insert(parts, "")
  table.insert(parts, "---")
  table.insert(parts, "")

  -- Add working directory context
  if opts.cwd then
    table.insert(parts, "Working directory: " .. opts.cwd)
  end

  -- Add file context
  if opts.filepath then
    table.insert(parts, "File: " .. opts.filepath)
  end

  -- Add line range
  if opts.start_line and opts.end_line then
    table.insert(parts, string.format("Lines %d-%d:", opts.start_line, opts.end_line))
  end

  table.insert(parts, "")

  -- Add code block with filetype
  local filetype = opts.filetype or ""
  table.insert(parts, "```" .. filetype)

  if opts.code and opts.start_line then
    -- Add line numbers to help Claude reference specific lines
    local lines = vim.split(opts.code, "\n", { plain = true })
    for i, line in ipairs(lines) do
      local line_num = opts.start_line + i - 1
      table.insert(parts, string.format("%4d | %s", line_num, line))
    end
  elseif opts.code then
    table.insert(parts, opts.code)
  end

  table.insert(parts, "```")
  table.insert(parts, "")

  -- Add user's request
  table.insert(parts, "Request: " .. (opts.user_prompt or ""))

  return table.concat(parts, "\n")
end

--- Build prompt from a selection context
---@param selection table The selection from context.get_visual_selection()
---@param user_prompt string The user's request
---@return string prompt
function M.build_from_selection(selection, user_prompt)
  local code = table.concat(selection.lines, "\n")

  return M.build({
    filepath = selection.filepath,
    filetype = selection.filetype,
    code = code,
    start_line = selection.start_line,
    end_line = selection.end_line,
    user_prompt = user_prompt,
    cwd = vim.fn.getcwd(),
  })
end

return M
