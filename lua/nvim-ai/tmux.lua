-- nvim-ai.tmux: thin wrapper around the tmux commands the plugin needs.
local config = require("nvim-ai.config")

local M = {}

---@return boolean
function M.active()
	return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

---Run tmux and return stdout on success, nil plus stderr on failure.
---@param args string[]
---@return string|nil, string|nil
local function run(args)
	local out = vim.fn.system(args)
	if vim.v.shell_error ~= 0 then
		return nil, out
	end
	return out, nil
end

---List panes in the current window (or every window when configured).
---@return { id: string, session: string, title: string }[]
function M.list_panes()
	local opts = config.get()
	local args = { opts.tmux, "list-panes" }
	if opts.pane_search_all_windows then
		table.insert(args, "-a")
	end
	table.insert(args, "-F")
	table.insert(args, "#{pane_id}\t#{@nvim_ai_session}\t#{pane_title}")
	local out = run(args)
	if not out then
		return {}
	end
	local panes = {}
	for line in out:gmatch("[^\n]+") do
		local id, session, title = line:match("^(.-)\t(.-)\t(.*)$")
		if id and id ~= "" then
			panes[#panes + 1] = { id = id, session = session, title = title }
		end
	end
	return panes
end

---Find the pane currently running the given session.
---@param session_id string
---@return string|nil
function M.find_pane(session_id)
	local panes = M.list_panes()
	for _, pane in ipairs(panes) do
		if pane.session == session_id then
			return pane.id
		end
	end
	for _, pane in ipairs(panes) do
		if pane.title == session_id then
			return pane.id
		end
	end
	return nil
end

---@param pane string
---@return boolean
function M.select(pane)
	local _, err = run({ config.get().tmux, "select-pane", "-t", pane })
	if err then
		require("nvim-ai.util").notify("tmux select-pane failed: " .. err, vim.log.levels.WARN)
		return false
	end
	return true
end

---Tag a pane with the session id: title plus a private user option.
---@param pane string
---@param session_id string
---@return boolean
function M.name_pane(pane, session_id)
	local opts = config.get()
	local ok_title, err_title = run({ opts.tmux, "select-pane", "-t", pane, "-T", session_id })
	local ok_option, err_option =
		run({ opts.tmux, "set-option", "-p", "-t", pane, "@nvim_ai_session", session_id })
	if not ok_title or not ok_option then
		require("nvim-ai.util").notify(
			"tmux pane naming failed: " .. tostring(err_title or err_option or ""),
			vim.log.levels.WARN
		)
		return false
	end
	return true
end

---Split the current window and run `cmd` in a new pane.
---@param cmd string
---@param cwd string
---@return string|nil pane id
function M.split(cmd, cwd)
	local opts = config.get()
	local args = { opts.tmux, "split-window", opts.split }
	if opts.detach then
		table.insert(args, "-d")
	end
	table.insert(args, "-c")
	table.insert(args, cwd)
	table.insert(args, "-P")
	table.insert(args, "-F")
	table.insert(args, "#{pane_id}")
	table.insert(args, cmd)
	local out, err = run(args)
	if not out then
		require("nvim-ai.util").notify("tmux split-window failed: " .. tostring(err or ""), vim.log.levels.ERROR)
		return nil
	end
	return vim.trim(out)
end

---Paste text into a pane using bracketed paste, without submitting it.
---@param pane string
---@param text string
---@return boolean
function M.paste(pane, text)
	local opts = config.get()
	local path = vim.fn.tempname() .. ".txt"
	-- "b" keeps the file byte-exact, so no trailing newline is added.
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path, "b")
	local buffer = "nvim-ai-prefill"
	local _, load_err = run({ opts.tmux, "load-buffer", "-b", buffer, path })
	if load_err then
		vim.fn.delete(path)
		require("nvim-ai.util").notify("tmux load-buffer failed: " .. load_err, vim.log.levels.ERROR)
		return false
	end
	local _, paste_err = run({ opts.tmux, "paste-buffer", "-p", "-b", buffer, "-t", pane })
	run({ opts.tmux, "delete-buffer", "-b", buffer })
	vim.fn.delete(path)
	if paste_err then
		require("nvim-ai.util").notify("tmux paste-buffer failed: " .. paste_err, vim.log.levels.ERROR)
		return false
	end
	return true
end

return M
