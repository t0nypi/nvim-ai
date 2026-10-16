-- .nvim.lua
-- Prototype: editor-contextualized AI agent for Neovim.
--
-- Commands:
--   :AIContext      Ask for a request, then run `pi` in a tmux split pane,
--                   contextualized with the current file and cursor line.
--   :AIContextStop  Stop watching the .currentChange file.
--
-- Keymap:
--   <leader>ac      Same as :AIContext
--
-- How it works:
--   1. prompts for a request in the command line
--   2. saves the current buffer
--   3. if the repo has unstaged changes, asks whether to proceed; on "No"
--      it opens fugitive so you can review them
--   4. spawns `pi` in a tmux split pane with an appended system prompt that
--      carries the file/line context and the change-reporting contract
--   5. polls `<cwd>/.currentChange` and parses each
--      `filepath:line:col - <summary>` line into the quickfix list
--
-- NOTE: kept in a single .nvim.lua on purpose so it is easy to iterate on.
-- It is structured as a module (`local M = {}`) so it can later be moved to
-- `lua/<name>/init.lua` and required.

local M = {}

M.config = {
	command = "AIContext",
	stop_command = "AIContextStop",
	keymap = "<leader>ac",

	-- file the agent writes its change list to (relative to nvim's cwd)
	change_file = ".currentChange",

	-- tmux split-window orientation: "-h" = side-by-side, "-v" = stacked
	split = "-h",
	-- true => keep focus in Neovim (adds -d to tmux split-window)
	detach = false,

	-- polling interval (ms) for the .currentChange file
	poll_interval = 500,
	-- automatically open the quickfix window when the list is (re)populated
	open_quickfix = false,

	errorformat = "%f:%l:%c - %m",
}

local uv = vim.uv or vim.loop

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "AI Context" })
end

local function read_file(path)
	local fd = io.open(path, "r")
	if not fd then
		return nil
	end
	local content = fd:read("*a")
	fd:close()
	return content
end

local function git_root(dir)
	local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return vim.trim(out)
end

-- true only for unstaged modifications to tracked files (working tree vs index)
local function has_unstaged_changes(root)
	vim.fn.system({ "git", "-C", root, "diff", "--quiet" })
	-- `git diff --quiet` exits 1 when there are differences
	return vim.v.shell_error == 1
end

local function build_system_prompt(file, line)
	local change_path = vim.fs.joinpath(vim.fn.getcwd(), M.config.change_file)
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

local function temp_prompt_file(text)
	local path = vim.fn.tempname() .. ".md"
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
	return path
end

local function shelljoin(args)
	local escaped = {}
	for _, arg in ipairs(args) do
		escaped[#escaped + 1] = vim.fn.shellescape(arg)
	end
	return table.concat(escaped, " ")
end

local function pi_command(prompt, prompt_file)
	-- `--` stops option parsing so a request starting with `-` is not treated
	-- as a flag. The long system prompt is written to a file because it
	-- contains backticks/quotes that are painful to shell-quote.
	return shelljoin({ "pi", "--append-system-prompt", prompt_file, "--", prompt })
end

local function spawn_in_tmux(cmd, cwd)
	local args = { "tmux", "split-window", M.config.split }
	if M.config.detach then
		table.insert(args, "-d")
	end
	table.insert(args, "-c")
	table.insert(args, cwd)
	table.insert(args, cmd)
	local out = vim.fn.system(args)
	if vim.v.shell_error ~= 0 then
		notify("tmux split-window failed: " .. out, vim.log.levels.ERROR)
		return false
	end
	return true
end

local function spawn_in_nvim(cmd)
	vim.cmd("vsplit")
	vim.fn.termopen(cmd)
	vim.cmd("startinsert")
	return true
end

local function open_fugitive()
	if vim.fn.exists(":Git") == 2 then
		vim.cmd("vert Git")
	else
		notify("fugitive not found; opening `git diff`", vim.log.levels.WARN)
		vim.cmd("vsplit")
		vim.fn.termopen("git diff")
		vim.cmd("startinsert")
	end
end

local function update_quickfix(content)
	local lines = vim.split(content or "", "\n", { plain = true })
	local filtered = {}
	for _, line in ipairs(lines) do
		-- keep only lines that look like `filepath:line:col - summary`
		if line:match(":%d+:%d+ %- ") then
			filtered[#filtered + 1] = line
		end
	end
	if #filtered == 0 then
		vim.fn.setqflist({}, " ")
		return 0
	end
	vim.fn.setqflist({}, " ", {
		title = "AI changes",
		efm = M.config.errorformat,
		lines = filtered,
	})
	return #vim.fn.getqflist()
end

function M.stop_watch()
	if M.timer then
		M.timer:stop()
		if not M.timer:is_closing() then
			M.timer:close()
		end
		M.timer = nil
	end
end

local function start_watch(change_path)
	M.stop_watch()
	M.last_content = "__uninitialized__"
	local timer = uv.new_timer()
	M.timer = timer
	timer:start(
		0,
		M.config.poll_interval,
		vim.schedule_wrap(function()
			local content = read_file(change_path) or ""
			if content == M.last_content then
				return
			end
			M.last_content = content
			local count = update_quickfix(content)
			if count and count > 0 then
				notify(string.format("%d AI change(s) — :copen to review", count))
				if M.config.open_quickfix then
					vim.cmd("copen")
				end
			end
		end)
	)
end

function M.run()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		notify("Current buffer has no file name", vim.log.levels.ERROR)
		return
	end
	if vim.bo.buftype ~= "" then
		notify("Current buffer is not a normal file", vim.log.levels.ERROR)
		return
	end

	local prompt = vim.fn.input("AI request: ")
	if prompt == "" then
		notify("Empty request, aborted")
		return
	end

	-- Save the buffer before the agent reads/modifies it.
	local ok, err = pcall(vim.cmd, "write")
	if not ok then
		notify("Failed to save file: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	local cwd = vim.fn.getcwd()
	local root = git_root(cwd)
	if root and has_unstaged_changes(root) then
		local choice = vim.fn.confirm(
			"You have unstaged changes. Proceed anyway?",
			"&Yes\n&No",
			2
		)
		if choice ~= 1 then
			open_fugitive()
			return
		end
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local change_path = vim.fs.joinpath(cwd, M.config.change_file)
	-- reset so we only react to what this run produces
	vim.fn.writefile({}, change_path)

	local prompt_file = temp_prompt_file(build_system_prompt(file, line))
	local cmd = pi_command(prompt, prompt_file)

	start_watch(change_path)

	local spawned
	if vim.env.TMUX and vim.env.TMUX ~= "" then
		spawned = spawn_in_tmux(cmd, cwd)
	else
		notify("Not inside tmux; falling back to a Neovim terminal", vim.log.levels.WARN)
		spawned = spawn_in_nvim(cmd)
	end

	if not spawned then
		M.stop_watch()
	end
end

vim.api.nvim_create_user_command(M.config.command, function()
	M.run()
end, { force = true, desc = "AI request in editor context" })

vim.api.nvim_create_user_command(M.config.stop_command, function()
	M.stop_watch()
end, { force = true, desc = "Stop watching .currentChange" })

vim.keymap.set("n", M.config.keymap, function()
	M.run()
end, { desc = "AI request in editor context" })

vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		M.stop_watch()
	end,
})

return M
