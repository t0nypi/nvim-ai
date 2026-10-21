-- nvim-ai.config: default options and setup-time merging.
local M = {}

M.defaults = {
	-- Command and mapping used to launch a request.
	command = "AIContext",
	stop_command = "AIContextStop",
	keymap = "<leader>ai",
	-- Visual-mode mapping. When nil it falls back to `keymap`; set to false
	-- to disable the visual mapping.
	visual_keymap = nil,

	-- Agent executable and extra arguments. `extra_args` are inserted before
	-- the append-system-prompt flag, so they can carry model/provider flags.
	cmd = "pi",
	extra_args = {},
	append_system_prompt_flag = "--append-system-prompt",

	-- File the agent writes its change list to, relative to Neovim's cwd.
	change_file = ".currentChange",

	-- tmux split-window orientation: "-h" = side-by-side, "-v" = stacked.
	split = "-h",
	-- true => keep focus in Neovim (adds -d to tmux split-window).
	detach = false,
	-- tmux executable.
	tmux = "tmux",

	-- Polling interval (ms) for the change file.
	poll_interval = 500,
	-- Automatically open the quickfix window when the list is (re)populated.
	open_quickfix = false,
	-- errorformat used to parse the change file.
	errorformat = "%f:%l:%c - %m",
}

local options = vim.deepcopy(M.defaults)

--- Merge user options over the defaults and store them.
---@param opts table|nil
---@return table
function M.setup(opts)
	options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	return options
end

---@return table
function M.get()
	return options
end

return M
