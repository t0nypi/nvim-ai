-- nvim-ai: editor-contextualized AI agent for Neovim.
--
-- Public API:
--   require("nvim-ai").setup(opts)  configure and register commands/keymap
--   require("nvim-ai").run()        launch a request
--   require("nvim-ai").stop()       stop watching the change file
--   require("nvim-ai").get_config() current merged options
local config = require("nvim-ai.config")
local agent = require("nvim-ai.agent")
local quickfix = require("nvim-ai.quickfix")
local selection = require("nvim-ai.selection")

local M = {}

---Configure the plugin and register its commands, keymap and autocmds.
---@param opts table|nil
---@return table self
function M.setup(opts)
	local options = config.setup(opts)

	vim.api.nvim_create_user_command(options.command, function()
		M.run()
	end, { force = true, desc = "AI request in editor context" })

	vim.api.nvim_create_user_command(options.continue_command, function()
		M.run_continue()
	end, { force = true, desc = "Continue the latest AI session in editor context" })

	vim.api.nvim_create_user_command(options.stop_command, function()
		M.stop()
	end, { force = true, desc = "Stop watching the AI change file" })

	vim.api.nvim_create_user_command(options.refresh_command, function()
		M.refresh()
	end, { force = true, desc = "Reload current changes in quickfix list" })

	vim.keymap.set("n", options.keymap, function()
		M.run()
	end, { desc = "AI request in editor context" })

	vim.keymap.set("n", options.continue_keymap, function()
		M.run_continue()
	end, { desc = "Continue the latest AI session in editor context" })

	local visual_keymap = options.visual_keymap
	if visual_keymap == nil then
		visual_keymap = options.keymap
	end
	if visual_keymap then
		vim.keymap.set("x", visual_keymap, function()
			local range = selection.range()
			vim.cmd("normal! \27")
			M.run({ range = range })
		end, { desc = "AI request for visual selection" })
	end

	local continue_visual_keymap = options.continue_visual_keymap
	if continue_visual_keymap == nil then
		continue_visual_keymap = options.continue_keymap
	end
	if continue_visual_keymap then
		vim.keymap.set("x", continue_visual_keymap, function()
			local range = selection.range()
			vim.cmd("normal! \27")
			M.run_continue({ range = range })
		end, { desc = "Continue the latest AI session for visual selection" })
	end

	local group = vim.api.nvim_create_augroup("NvimAi", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.stop()
		end,
	})

	return M
end

---Launch a contextual request.
M.run = agent.run

---Continue the latest existing session for the current cwd.
M.run_continue = agent.run_continue

M.stop = quickfix.stop

---One-shot refresh of the quickfix list from the change file.
M.refresh = quickfix.refresh

---@return table current merged options
M.get_config = config.get

return M
