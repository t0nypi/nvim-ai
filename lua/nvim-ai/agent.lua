-- nvim-ai.agent: orchestrates a single contextual request.
local config = require("nvim-ai.config")
local util = require("nvim-ai.util")
local prompt = require("nvim-ai.prompt")
local quickfix = require("nvim-ai.quickfix")
local session = require("nvim-ai.session")
local tmux = require("nvim-ai.tmux")

local M = {}

---Build the shell command that launches a new agent session.
---@param request string
---@param prompt_file string
---@param session_id string
---@return string
local function agent_command(request, prompt_file, session_id)
	local opts = config.get()
	local args = { opts.cmd }
	vim.list_extend(args, opts.extra_args)
	table.insert(args, opts.append_system_prompt_flag)
	table.insert(args, prompt_file)
	table.insert(args, "--session-id")
	table.insert(args, session_id)
	-- `--` stops option parsing so a request starting with `-` is not treated
	-- as a flag.
	table.insert(args, "--")
	table.insert(args, request)
	return util.shelljoin(args)
end

---Build the shell command that resumes an existing agent session. There is no
---request positional: the extension prefills the editor instead.
---@param session_id string
---@param prefill_file string
---@param contract_file string
---@return string
local function continue_command(session_id, prefill_file, contract_file)
	local opts = config.get()
	local args = { opts.cmd }
	vim.list_extend(args, opts.extra_args)
	table.insert(args, opts.append_system_prompt_flag)
	table.insert(args, contract_file)
	table.insert(args, "--session-id")
	table.insert(args, session_id)
	table.insert(args, "-e")
	table.insert(args, opts.prefill_extension)
	table.insert(args, opts.prefill_flag)
	table.insert(args, prefill_file)
	return util.shelljoin(args)
end

---Write text byte-exactly (no trailing newline) to a temp file.
---@param text string
---@param ext string|nil
---@return string
local function write_raw_temp(text, ext)
	local path = vim.fn.tempname() .. (ext or "")
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path, "b")
	return path
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

---Collect the file and cursor/selection context for the current buffer.
---@param ctx table|nil `{ range = NvimAiRange }` for a visual selection
---@return NvimAiContext
function M.context_for(ctx)
	ctx = ctx or {}
	local file = vim.api.nvim_buf_get_name(0)
	local display_file = util.relpath(file, vim.fn.getcwd())
	if ctx.range then
		return { file = file, display_file = display_file, range = ctx.range }
	end
	return {
		file = file,
		display_file = display_file,
		line = vim.api.nvim_win_get_cursor(0)[1],
	}
end

---@return boolean
local function valid_buffer()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		util.notify("Current buffer has no file name", vim.log.levels.ERROR)
		return false
	end
	if vim.bo.buftype ~= "" then
		util.notify("Current buffer is not a normal file", vim.log.levels.ERROR)
		return false
	end
	return true
end

---@return boolean
local function save_buffer()
	local ok, err = pcall(vim.cmd, "write")
	if not ok then
		util.notify("Failed to save file: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

---Ask for a request and launch the contextual agent.
---@param ctx table|nil optional context; `{ range = NvimAiRange }` for a visual
---                         selection, otherwise the cursor line is used
function M.run(ctx)
	ctx = ctx or {}
	local opts = config.get()
	if not valid_buffer() then
		return
	end

	-- Save the invoking buffer before the request buffer replaces the window,
	-- so the agent reads/modifies a consistent on-disk state.
	if not save_buffer() then
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

	local context = M.context_for(ctx)

	-- Open the request buffer first; everything below runs once the user saves it.
	request_from_buffer(function(request)
		local change_path = vim.fs.joinpath(cwd, opts.change_file)
		-- reset so we only react to what this run produces
		vim.fn.writefile({}, change_path)

		local session_id = session.generate_id()
		local prompt_file = prompt.write_temp_file(prompt.build(context))
		local cmd = agent_command(request, prompt_file, session_id)

		quickfix.start(change_path)

		local spawned
		if tmux.active() then
			local pane = tmux.split(cmd, cwd)
			if pane then
				session.record(cwd, session_id)
				tmux.name_pane(pane, session_id)
			end
			spawned = pane ~= nil
		else
			util.notify("Not inside tmux; falling back to a Neovim terminal", vim.log.levels.WARN)
			spawned = spawn_in_nvim(cmd)
			if spawned then
				session.record(cwd, session_id)
			end
		end

		if not spawned then
			quickfix.stop()
		end
	end)
end

---Continue the newest existing session for the current cwd, prefilling pi's
---editor with the current file/line (or visual range) context.
---@param ctx table|nil same shape as `run`
function M.run_continue(ctx)
	ctx = ctx or {}
	local opts = config.get()
	if not valid_buffer() then
		return
	end
	if not save_buffer() then
		return
	end

	local cwd = vim.fn.getcwd()
	local resolved = session.resolve(cwd)
	if not resolved then
		util.notify("No pi session found for this cwd; run :" .. opts.command .. " first", vim.log.levels.WARN)
		return
	end

	local context = M.context_for(ctx)
	local prefill = prompt.build_prefill(context)
	local change_path = vim.fs.joinpath(cwd, opts.change_file)

	if tmux.active() then
		local pane = tmux.find_pane(resolved.id)
		if pane then
			-- Case A: the session is already running in this tmux window.
			tmux.select(pane)
			tmux.paste(pane, prefill)
			-- Refresh the watcher without touching .currentChange: same session.
			quickfix.start(change_path)
			return
		end

		-- Case B: resume in a new pane and let the extension prefill the editor.
		local contract_file = prompt.write_temp_file(prompt.build_contract())
		local prefill_file = write_raw_temp(prefill, ".txt")
		local cmd = continue_command(resolved.id, prefill_file, contract_file)
		local new_pane = tmux.split(cmd, cwd)
		if new_pane then
			tmux.name_pane(new_pane, resolved.id)
			session.record(cwd, resolved.id)
			quickfix.start(change_path)
		end
		return
	end

	-- Non-tmux fallback: the extension still prefills the TUI in Neovim.
	util.notify("Not inside tmux; falling back to a Neovim terminal", vim.log.levels.WARN)
	local contract_file = prompt.write_temp_file(prompt.build_contract())
	local prefill_file = write_raw_temp(prefill, ".txt")
	local cmd = continue_command(resolved.id, prefill_file, contract_file)
	if spawn_in_nvim(cmd) then
		session.record(cwd, resolved.id)
		quickfix.start(change_path)
	end
end

return M
