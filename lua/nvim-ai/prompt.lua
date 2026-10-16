-- nvim-ai.prompt: builds the system prompt appended to the agent.
local config = require("nvim-ai.config")

local M = {}

---Build the appended system prompt for a given file/line context.
---@param file string absolute path of the invoking buffer
---@param line integer 1-based cursor line
---@return string
function M.build(file, line)
	local change_path = vim.fs.joinpath(vim.fn.getcwd(), config.get().change_file)
	local parts = {
		"You have been invoked by the user to satisfy a request. "
			.. "The request happens in the context of `"
			.. file
			.. "` at line `"
			.. line
			.. "`. "
			.. "If you need to change files in order to satisfy the user request, don't just produce a summary at the end of what you have done; "
			.. "you should also put an inline comment for each change you do (if the filetype has a comment format), explaining the change in the comment. "
			.. "General notes, clarifying questions and other broader comments should still be reported in the summary of the agent's session round.",
		"",
		"You may keep talking with the user in this same session across multiple rounds of changes. "
			.. "Whenever you make changes — in this round or in any later round — you must always report them in the change file described below, "
			.. "and you must rewrite that file from scratch every time.",
		"",
		"The file must always describe the whole session: include every change you have made since the start of the session that is still present in the current state of the files. "
			.. "In other words, it is the first round plus any later adjustments, minus anything that a later request replaced or reverted. "
			.. "Never report only the changes from the most recent round; the file must be the complete and current picture of the session's changes.",
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

---Write prompt text to a unique temp file and return its path.
---@param text string
---@return string
function M.write_temp_file(text)
	local path = vim.fn.tempname() .. ".md"
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
	return path
end

return M
