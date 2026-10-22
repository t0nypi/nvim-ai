-- nvim-ai.prompt: builds the system prompt appended to the agent.
local config = require("nvim-ai.config")

local M = {}

---@class NvimAiRange
---@field srow integer 1-based start line
---@field scol integer 1-based start column
---@field erow integer 1-based end line
---@field ecol integer 1-based end column
---@field mode string|nil visual mode ("v", "V" or block)

---@class NvimAiContext
---@field file string absolute path of the invoking buffer
---@field display_file string|nil path shown to the agent (usually relative to cwd)
---@field line integer|nil 1-based cursor line (normal mode)
---@field range NvimAiRange|nil visual selection (visual mode)

---Build only the change-file/quickfix contract, without any location sentence.
---This is reused when resuming a session, where the location lives in the
---editor prefill instead of the system prompt.
---@return string
function M.build_contract()
	local change_path = vim.fs.joinpath(vim.fn.getcwd(), config.get().change_file)
	local parts = {
		"If you need to change files in order to satisfy the user request, don't just produce a summary at the end of what you have done; "
		..
		"you should also put an inline comment for each change you do (if the filetype has a comment format), explaining the change in the comment. "
		..
		"General notes, clarifying questions and other broader comments should still be reported in the summary of the agent's session round.",
		"",
		"If the request of the user is to explain or describe some code, you should create a path in the codebase by leaving comments in each relevant point."
		..
		"When creating the quickfix list, the points in code with these comments should be in the correct order to have a good and clear explaination",
		"You may keep talking with the user in this same session across multiple rounds of changes. "
		..
		"Whenever you make changes — in this round or in any later round — you must always report them in the change file described below, "
		.. "and you must rewrite that file from scratch every time.",
		"",
		"The file must always describe the whole session: include every change you have made since the start of the session that is still present in the current state of the files. "
		..
		"In other words, it is the first round plus any later adjustments, minus anything that a later request replaced or reverted. "
		..
		"Never report only the changes from the most recent round; the file must be the complete and current picture of the session's changes.",
		"",
		"Produce that list of positions in the file `"
		.. change_path
		.. "`, one position per line, using exactly this format:",
		"",
		"    filepath:line:col - <very short summary of change>",
		"",
		"Use absolute file paths. List the positions in a meaningful order (for example top-to-bottom per file) so the user can review them quickly in the quickfix list.",
		"If no changes are still present, leave the file empty.",
	}
	return table.concat(parts, "\n")
end

---Build the appended system prompt for a given context.
---@param context NvimAiContext
---@return string
function M.build(context)
	local location
	if context.range then
		local r = context.range
		if r.mode == "V" then
			location = string.format(
				"The request happens in the context of `%s`, specifically lines `%d` to `%d`.",
				context.file,
				r.srow,
				r.erow
			)
		else
			location = string.format(
				"The request happens in the context of `%s`, specifically the selection from line `%d`, column `%d` to line `%d`, column `%d`.",
				context.file,
				r.srow,
				r.scol,
				r.erow,
				r.ecol
			)
		end
	else
		location = string.format(
			"The request happens in the context of `%s` at line `%d`.",
			context.file,
			context.line
		)
	end
	return "You have been invoked by the user to satisfy a request. " .. location .. " " .. M.build_contract()
end

---Build the sentence prefilled into pi's editor when continuing a session.
---Uses the display path (relative to cwd when possible) and never ends with a
---newline, so pasting it does not submit the request.
---@param context NvimAiContext
---@return string
function M.build_prefill(context)
	local file = context.display_file or context.file
	if context.range then
		local r = context.range
		local range
		if r.mode == "V" then
			range = string.format("%d-%d", r.srow, r.erow)
		else
			range = string.format("%d:%d-%d:%d", r.srow, r.scol, r.erow, r.ecol)
		end
		return string.format(
			"Now, with particular focus on file: %s, in range: %s, satisfy the following request:",
			file,
			range
		)
	end
	return string.format(
		"Now, with particular focus on file: %s, at line: %d, satisfy the following request:",
		file,
		context.line
	)
end

---Write prompt text to a unique temp file and return its path.
---@param text string
---@return string
function M.write_temp_file(text)
	local path = vim.fn.tempname() .. ".md"
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
	return path
end

return M
