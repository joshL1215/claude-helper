-- UI module exports for claude-helper.nvim
local M = {}

M.input = require("claude-helper.ui.input")
M.diff = require("claude-helper.ui.diff")
M.inline_diff = require("claude-helper.ui.inline_diff")
M.confirmation = require("claude-helper.ui.confirmation")
M.progress = require("claude-helper.ui.progress")
M.proposal = require("claude-helper.ui.proposal")

return M
