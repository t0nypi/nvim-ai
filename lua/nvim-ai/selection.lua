-- nvim-ai.selection: turns the active visual selection into a 1-based range.
local M = {}

---@class NvimAiRange
---@field srow integer 1-based start line
---@field scol integer 1-based start column
---@field erow integer 1-based end line
---@field ecol integer 1-based end column
---@field mode string|nil visual mode ("v", "V" or block)

---Capture the active visual selection.
---Must be called while visual mode is still active.
---@return NvimAiRange
function M.range()
	local anchor = vim.fn.getpos("v")
	local cursor = vim.fn.getpos(".")
	local srow, scol = anchor[2], anchor[3]
	local erow, ecol = cursor[2], cursor[3]
	-- normalize so that start <= end
	if srow > erow or (srow == erow and scol > ecol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end
	-- the end column can point one past the end of the line
	local line = vim.api.nvim_buf_get_lines(0, erow - 1, erow, false)[1]
	local maxcol = math.max(line and #line or 0, 1)
	if ecol > maxcol then
		ecol = maxcol
	end
	return { srow = srow, scol = scol, erow = erow, ecol = ecol, mode = vim.fn.mode() }
end

return M
