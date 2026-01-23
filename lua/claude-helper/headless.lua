-- Headless Claude execution for claude-helper.nvim
-- Runs Claude in headless mode for proposal-based workflows
local M = {}

local config = require("claude-helper.config")
local schema = require("claude-helper.schema")

-- Track state of headless execution
local state = {
  status = "idle", -- "idle" | "running" | "completed" | "error"
  job_id = nil,
  original_files = {}, -- {[filepath] = content}
  changed_files = {}, -- {[filepath] = {old = ..., new = ..., status = "modified"|"added"|"deleted"}}
  stderr_output = {},
  stdout_output = {},
  on_complete = nil,
  on_error = nil,
  timeout_timer = nil,
}

--- Get all open buffer file paths
---@return table List of absolute file paths
local function get_open_buffer_paths()
  local paths = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= "" and vim.fn.filereadable(path) == 1 then
        table.insert(paths, path)
      end
    end
  end
  return paths
end

--- Read file contents from disk
---@param filepath string
---@return string|nil content, string|nil error
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
---@return boolean success, string|nil error
local function write_file(filepath, content)
  local file = io.open(filepath, "w")
  if not file then
    return false, "Could not write file: " .. filepath
  end
  file:write(content)
  file:close()
  return true, nil
end

--- Snapshot files before Claude runs
---@param filepaths table|nil List of file paths to snapshot (defaults to open buffers)
function M.snapshot_files(filepaths)
  filepaths = filepaths or get_open_buffer_paths()
  state.original_files = {}

  for _, filepath in ipairs(filepaths) do
    local content = read_file(filepath)
    if content then
      state.original_files[filepath] = content
    end
  end
end

--- Detect changes by comparing disk state to snapshots
---@return table changes List of {filepath, old, new, status}
function M.detect_changes()
  local changes = {}

  -- Check files we have snapshots for
  for filepath, original_content in pairs(state.original_files) do
    local current_content = read_file(filepath)

    if current_content == nil then
      -- File was deleted
      table.insert(changes, {
        filepath = filepath,
        old = original_content,
        new = nil,
        status = "deleted",
      })
    elseif current_content ~= original_content then
      -- File was modified
      table.insert(changes, {
        filepath = filepath,
        old = original_content,
        new = current_content,
        status = "modified",
      })
    end
  end

  -- Check for new files in the working directory
  -- (This is a simplified check - Claude might create files anywhere)
  local cwd = vim.fn.getcwd()
  local git_files = vim.fn.systemlist("git ls-files --others --exclude-standard 2>/dev/null")
  if vim.v.shell_error == 0 then
    for _, relpath in ipairs(git_files) do
      local filepath = cwd .. "/" .. relpath
      if not state.original_files[filepath] then
        local content = read_file(filepath)
        if content then
          table.insert(changes, {
            filepath = filepath,
            old = nil,
            new = content,
            status = "added",
          })
        end
      end
    end
  end

  state.changed_files = {}
  for _, change in ipairs(changes) do
    state.changed_files[change.filepath] = change
  end

  return changes
end

--- Revert all changed files to their original state
---@return boolean success
---@return string|nil error
function M.revert_changes()
  local errors = {}

  for filepath, change in pairs(state.changed_files) do
    if change.status == "deleted" or change.status == "modified" then
      -- Restore original content
      local ok, err = write_file(filepath, change.old)
      if not ok then
        table.insert(errors, err)
      end
    elseif change.status == "added" then
      -- Delete the new file
      local ok = os.remove(filepath)
      if not ok then
        table.insert(errors, "Could not delete file: " .. filepath)
      end
    end
  end

  -- Reload affected buffers
  for filepath, _ in pairs(state.changed_files) do
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) == filepath then
        if vim.api.nvim_buf_is_loaded(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit!")
          end)
        end
        break
      end
    end
  end

  -- Clear state
  state.original_files = {}
  state.changed_files = {}

  if #errors > 0 then
    return false, table.concat(errors, "\n")
  end
  return true, nil
end

--- Accept changes (clear snapshots, changes already on disk)
function M.accept_changes()
  state.original_files = {}
  state.changed_files = {}
end

--- Cancel a running Claude job
function M.cancel()
  if state.job_id then
    vim.fn.jobstop(state.job_id)
    state.job_id = nil
  end
  if state.timeout_timer then
    state.timeout_timer:stop()
    state.timeout_timer = nil
  end
  state.status = "idle"
end

--- Get current status
---@return string status "idle" | "running" | "completed" | "error"
function M.get_status()
  return state.status
end

--- Check if Claude is currently running
---@return boolean
function M.is_running()
  return state.status == "running"
end

--- Get changed files
---@return table
function M.get_changed_files()
  return state.changed_files
end

--- Run Claude in headless mode
---@param prompt string The prompt to send to Claude
---@param opts table Options: on_complete, on_error, timeout_ms
function M.run(prompt, opts)
  opts = opts or {}
  local cfg = config.get()

  -- Check if already running
  if state.status == "running" then
    vim.notify("Claude is already running", vim.log.levels.WARN)
    return
  end

  -- Check if claude is available
  local claude_path = cfg.headless and cfg.headless.claude_path or "claude"
  if vim.fn.executable(claude_path) ~= 1 then
    vim.notify("Claude CLI not found: " .. claude_path, vim.log.levels.ERROR)
    if opts.on_error then
      opts.on_error("Claude CLI not found")
    end
    return
  end

  -- Reset state
  state.status = "running"
  state.stderr_output = {}
  state.stdout_output = {}
  state.on_complete = opts.on_complete
  state.on_error = opts.on_error

  -- Build command
  local cmd = { claude_path, "-p", prompt }

  -- Set up timeout
  local timeout_ms = opts.timeout_ms or (cfg.headless and cfg.headless.timeout_ms) or 300000
  state.timeout_timer = vim.uv.new_timer()
  state.timeout_timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    if state.status == "running" then
      M.cancel()
      state.status = "error"
      vim.notify("Claude timed out", vim.log.levels.ERROR)
      if state.on_error then
        state.on_error("Timeout after " .. (timeout_ms / 1000) .. " seconds")
      end
    end
  end))

  -- Run the job
  state.job_id = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(state.stdout_output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(state.stderr_output, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      -- Stop timeout timer
      if state.timeout_timer then
        state.timeout_timer:stop()
        state.timeout_timer = nil
      end

      state.job_id = nil

      vim.schedule(function()
        if exit_code == 0 then
          state.status = "completed"
          if state.on_complete then
            state.on_complete()
          end
        else
          state.status = "error"
          local error_msg = table.concat(state.stderr_output, "\n")
          if error_msg == "" then
            error_msg = "Claude exited with code " .. exit_code
          end
          vim.notify("Claude error: " .. error_msg, vim.log.levels.ERROR)
          if state.on_error then
            state.on_error(error_msg)
          end
        end
      end)
    end,
  })

  if state.job_id == 0 or state.job_id == -1 then
    state.status = "error"
    if state.timeout_timer then
      state.timeout_timer:stop()
      state.timeout_timer = nil
    end
    vim.notify("Failed to start Claude", vim.log.levels.ERROR)
    if opts.on_error then
      opts.on_error("Failed to start Claude job")
    end
  else
    -- Close stdin immediately so Claude doesn't wait for input
    vim.fn.chanclose(state.job_id, "stdin")
  end
end

--- Reload buffers that have changed on disk
function M.reload_changed_buffers()
  for filepath, _ in pairs(state.changed_files) do
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) == filepath then
        if vim.api.nvim_buf_is_loaded(bufnr) then
          -- Check if buffer has unsaved changes
          if vim.bo[bufnr].modified then
            vim.notify("Buffer has unsaved changes: " .. filepath, vim.log.levels.WARN)
          else
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("edit!")
            end)
          end
        end
        break
      end
    end
  end
end

--- Run Claude in proposal mode (JSON output, no file tools)
--- Claude proposes changes but cannot modify files directly
---@param prompt string The prompt to send to Claude
---@param opts table Options: on_complete(proposal), on_error(err), timeout_ms
function M.run_proposal(prompt, opts)
  opts = opts or {}
  local cfg = config.get()

  -- Check if already running
  if state.status == "running" then
    vim.notify("Claude is already running", vim.log.levels.WARN)
    return
  end

  -- Check if claude is available
  local claude_path = cfg.headless and cfg.headless.claude_path or "claude"
  if vim.fn.executable(claude_path) ~= 1 then
    vim.notify("Claude CLI not found: " .. claude_path, vim.log.levels.ERROR)
    if opts.on_error then
      opts.on_error("Claude CLI not found")
    end
    return
  end

  -- Reset state
  state.status = "running"
  state.stderr_output = {}
  state.stdout_output = {}
  state.on_complete = opts.on_complete
  state.on_error = opts.on_error

  -- Build command with JSON output and disabled tools
  -- --output-format json gives structured output
  -- --tools "" disables file modification tools
  local cmd = {
    claude_path,
    "-p",
    prompt,
    "--output-format",
    "json",
    "--tools",
    "",
  }

  -- Set up timeout
  local timeout_ms = opts.timeout_ms or (cfg.headless and cfg.headless.timeout_ms) or 300000
  state.timeout_timer = vim.uv.new_timer()
  state.timeout_timer:start(timeout_ms, 0, vim.schedule_wrap(function()
    if state.status == "running" then
      M.cancel()
      state.status = "error"
      vim.notify("Claude timed out", vim.log.levels.ERROR)
      if state.on_error then
        state.on_error("Timeout after " .. (timeout_ms / 1000) .. " seconds")
      end
    end
  end))

  -- Run the job
  state.job_id = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(state.stdout_output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(state.stderr_output, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      -- Stop timeout timer
      if state.timeout_timer then
        state.timeout_timer:stop()
        state.timeout_timer = nil
      end

      state.job_id = nil

      vim.schedule(function()
        if exit_code == 0 then
          state.status = "completed"

          -- Parse JSON output
          local output = table.concat(state.stdout_output, "\n")

          -- The JSON output from Claude CLI wraps the response
          -- Try to extract the result text which contains our JSON proposal
          local ok, json_response = pcall(vim.json.decode, output)
          if ok and json_response and json_response.result then
            -- Extract the text content from the result
            local text_content = ""
            if type(json_response.result) == "string" then
              text_content = json_response.result
            elseif type(json_response.result) == "table" then
              -- The result might be an array of content blocks
              for _, block in ipairs(json_response.result) do
                if type(block) == "table" and block.type == "text" and block.text then
                  text_content = text_content .. block.text
                elseif type(block) == "string" then
                  text_content = text_content .. block
                end
              end
            end

            -- Parse the proposal from the text content
            local proposal, parse_err = schema.parse(text_content)
            if proposal then
              if state.on_complete then
                state.on_complete(proposal)
              end
            else
              state.status = "error"
              local err_msg = "Failed to parse proposal: " .. (parse_err or "unknown error")
              vim.notify(err_msg, vim.log.levels.ERROR)
              if state.on_error then
                state.on_error(err_msg)
              end
            end
          else
            -- Try parsing the raw output as a proposal directly
            local proposal, parse_err = schema.parse(output)
            if proposal then
              if state.on_complete then
                state.on_complete(proposal)
              end
            else
              state.status = "error"
              local err_msg = "Failed to parse Claude response: " .. (parse_err or "invalid JSON")
              vim.notify(err_msg, vim.log.levels.ERROR)
              if state.on_error then
                state.on_error(err_msg)
              end
            end
          end
        else
          state.status = "error"
          local error_msg = table.concat(state.stderr_output, "\n")
          if error_msg == "" then
            error_msg = "Claude exited with code " .. exit_code
          end
          vim.notify("Claude error: " .. error_msg, vim.log.levels.ERROR)
          if state.on_error then
            state.on_error(error_msg)
          end
        end
      end)
    end,
  })

  if state.job_id == 0 or state.job_id == -1 then
    state.status = "error"
    if state.timeout_timer then
      state.timeout_timer:stop()
      state.timeout_timer = nil
    end
    vim.notify("Failed to start Claude", vim.log.levels.ERROR)
    if opts.on_error then
      opts.on_error("Failed to start Claude job")
    end
  else
    -- Close stdin immediately so Claude doesn't wait for input
    vim.fn.chanclose(state.job_id, "stdin")
  end
end

--- Get stdout output from last run (useful for debugging)
---@return table
function M.get_stdout()
  return state.stdout_output
end

--- Get stderr output from last run (useful for debugging)
---@return table
function M.get_stderr()
  return state.stderr_output
end

return M
