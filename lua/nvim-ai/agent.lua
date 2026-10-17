-- nvim-ai.agent: orchestrates a single contextual request.
local config = require("nvim-ai.config")
local util = require("nvim-ai.util")
local prompt = require("nvim-ai.prompt")
local quickfix = require("nvim-ai.quickfix")

local M = {}

---Build the shell command that launches the agent.
---@param request string
---@param prompt_file string
---@return string
local function agent_command(request, prompt_file)
	local opts = config.get()
	local args = { opts.cmd }
	vim.list_extend(args, opts.extra_args)
	table.insert(args, opts.append_system_prompt_flag)
	table.insert(args, prompt_file)
	-- `--` stops option parsing so a request starting with `-` is not treated
	-- as a flag.
	table.insert(args, "--")
	table.insert(args, request)
	return util.shelljoin(args)
end

---@param cmd string
---@param cwd string
---@return boolean
local function spawn_in_tmux(cmd, cwd)
	local opts = config.get()
	local args = { opts.tmux, "split-window", opts.split }
	if opts.detach then
		table.insert(args, "-d")
	end
	table.insert(args, "-c")
	table.insert(args, cwd)
	table.insert(args, cmd)
	local out = vim.fn.system(args)
	if vim.v.shell_error ~= 0 then
		util.notify("tmux split-window failed: " .. out, vim.log.levels.ERROR)
		return false
	end
	return true
end

---@param cmd string
---@return boolean
local function spawn_in_nvim(cmd)
	vim.cmd("vsplit")
	vim.fn.termopen(cmd)
	vim.cmd("startinsert")
	return true
end

---Collect the request by opening an editable scratch buffer. The request is
---taken from the buffer's text when the user saves it with `:write`; the buffer
---is then closed and `on_submit` is called with the text.
---@param on_submit fun(request: string)
local function request_from_buffer(on_submit)
	-- `acwrite` makes `:write` fire `BufWriteCmd` instead of touching disk, so
	-- the buffer is purely in-memory and we control what happens on save.
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_name(buf, "AI request")

	-- Show the request buffer in a 7-line-high horizontal split pinned to the
	-- bottom of the editor and start typing right away.
	-- CHANGE: was a vertical split; use a bottom-anchored 7-line horizontal split.
	vim.cmd("botright 7split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.cmd("startinsert")

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		once = true,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local request = vim.trim(table.concat(lines, "\n"))
			-- mark clean so no "unsaved changes" prompt appears on deletion
			vim.bo[buf].modified = false
			-- delete outside the autocmd to avoid re-entrancy while writing
			vim.schedule(function()
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
				if request == "" then
					util.notify("Empty request, aborted")
					return
				end
				on_submit(request)
			end)
		end,
	})
end

---Ask for a request and launch the contextual agent.
---@param ctx table|nil optional context; `{ range = NvimAiRange }` for a visual
---                         selection, otherwise the cursor line is used
function M.run(ctx)
	ctx = ctx or {}
	local opts = config.get()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		util.notify("Current buffer has no file name", vim.log.levels.ERROR)
		return
	end
	if vim.bo.buftype ~= "" then
		util.notify("Current buffer is not a normal file", vim.log.levels.ERROR)
		return
	end

	-- Save the invoking buffer before the request buffer replaces the window,
	-- so the agent reads/modifies a consistent on-disk state.
	local ok, err = pcall(vim.cmd, "write")
	if not ok then
		util.notify("Failed to save file: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	local cwd = vim.fn.getcwd()
	local root = util.git_root(cwd)
	if root and util.has_unstaged_changes(root) then
		local choice = vim.fn.confirm("You have unstaged changes. Proceed anyway?", "&Yes\n&No", 2)
		if choice ~= 1 then
			util.open_fugitive()
			return
		end
	end

	local context
	if ctx.range then
		context = { file = file, range = ctx.range }
	else
		context = { file = file, line = vim.api.nvim_win_get_cursor(0)[1] }
	end

	-- Open the request buffer first; everything below runs once the user saves it.
	request_from_buffer(function(request)
		local change_path = vim.fs.joinpath(cwd, opts.change_file)
		-- reset so we only react to what this run produces
		vim.fn.writefile({}, change_path)

		local prompt_file = prompt.write_temp_file(prompt.build(context))
		local cmd = agent_command(request, prompt_file)

		quickfix.start(change_path)

		local spawned
		if vim.env.TMUX and vim.env.TMUX ~= "" then
			spawned = spawn_in_tmux(cmd, cwd)
		else
			util.notify("Not inside tmux; falling back to a Neovim terminal", vim.log.levels.WARN)
			spawned = spawn_in_nvim(cmd)
		end

		if not spawned then
			quickfix.stop()
		end
	end)
end

return M
