-- JSON schema and validation for change proposals
local M = {}

--- Validate a single change entry
---@param change table The change entry to validate
---@return boolean valid
---@return string|nil error
local function validate_change(change)
  if type(change) ~= "table" then
    return false, "Change must be a table"
  end

  if type(change.filepath) ~= "string" or change.filepath == "" then
    return false, "Change must have a non-empty filepath string"
  end

  if type(change.start_line) ~= "number" or change.start_line < 1 then
    return false, "Change must have a valid start_line (number >= 1)"
  end

  if type(change.end_line) ~= "number" or change.end_line < change.start_line then
    return false, "Change must have a valid end_line (number >= start_line)"
  end

  if type(change.new_content) ~= "string" then
    return false, "Change must have new_content string"
  end

  -- explanation is optional
  if change.explanation ~= nil and type(change.explanation) ~= "string" then
    return false, "explanation must be a string if provided"
  end

  return true, nil
end

--- Validate a proposal structure
---@param proposal table The proposal to validate
---@return boolean valid
---@return string|nil error
function M.validate(proposal)
  if type(proposal) ~= "table" then
    return false, "Proposal must be a table"
  end

  if type(proposal.changes) ~= "table" then
    return false, "Proposal must have a 'changes' array"
  end

  if #proposal.changes == 0 then
    return false, "Proposal must have at least one change"
  end

  for i, change in ipairs(proposal.changes) do
    local valid, err = validate_change(change)
    if not valid then
      return false, "Change #" .. i .. ": " .. err
    end
  end

  -- summary is optional but should be string if present
  if proposal.summary ~= nil and type(proposal.summary) ~= "string" then
    return false, "summary must be a string if provided"
  end

  return true, nil
end

--- Parse JSON string into a proposal
---@param json_str string The JSON string
---@return table|nil proposal
---@return string|nil error
function M.parse(json_str)
  if type(json_str) ~= "string" or json_str == "" then
    return nil, "Empty or invalid input"
  end

  -- Try to extract JSON from the response (Claude might include extra text)
  local json_start = json_str:find("{")
  local json_end = json_str:match(".*()}")

  if not json_start or not json_end then
    return nil, "No JSON object found in response"
  end

  local json_content = json_str:sub(json_start, json_end)

  local ok, result = pcall(vim.json.decode, json_content)
  if not ok then
    return nil, "JSON parse error: " .. tostring(result)
  end

  local valid, err = M.validate(result)
  if not valid then
    return nil, "Validation error: " .. err
  end

  return result, nil
end

--- Create an empty proposal structure
---@return table
function M.empty()
  return {
    summary = "",
    changes = {},
  }
end

--- Example proposal structure (for documentation/testing)
M.example = {
  summary = "Add error handling to the function",
  changes = {
    {
      filepath = "/path/to/file.lua",
      start_line = 10,
      end_line = 15,
      new_content = "-- new code here\nlocal result = nil",
      explanation = "Added nil check before accessing result",
    },
  },
}

return M
