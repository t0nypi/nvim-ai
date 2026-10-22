-- nvim-ai.config: default options and setup-time merging.
local M = {}

---Resolve the bundled prefill extension relative to this file's plugin root.
---@return string
local function default_prefill_extension()
	local source = debug.getinfo(1, "S").source:gsub("^@", "")
	local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
	return vim.fs.joinpath(root, "pi", "nvim-ai-prefill.ts")
end

M.defaults = {
	-- Command and mapping used to launch a request.
	command = "AIContext",
	stop_command = "AIContextStop",
	keymap = "<leader>ai",
	-- Visual-mode mapping. When nil it falls back to `keymap`; set to false
	-- to disable the visual mapping.
	visual_keymap = nil,

	-- Command and mapping used to continue the newest existing session.
	continue_command = "AIContextContinue",
	continue_keymap = "<leader>ac",
	-- Visual-mode continue mapping. When nil it falls back to `continue_keymap`.
	continue_visual_keymap = nil,

	-- Session identity and discovery.
	session_id_prefix = "nvim-ai",
	-- Override pi's session root (defaults to $PI_CODING_AGENT_SESSION_DIR or
	-- ~/.pi/agent/sessions).
	session_dir = nil,
	-- true => search panes in every tmux window, not just the current one.
	pane_search_all_windows = false,

	-- Extension that prefills pi's editor when resuming a session.
	prefill_extension = default_prefill_extension(),
	prefill_flag = "--nvim-ai-prefill-file",

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
