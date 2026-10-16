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

local M = {}

---Configure the plugin and register its commands, keymap and autocmds.
---@param opts table|nil
---@return table self
function M.setup(opts)
	local options = config.setup(opts)

	vim.api.nvim_create_user_command(options.command, function()
		M.run()
	end, { force = true, desc = "AI request in editor context" })

	vim.api.nvim_create_user_command(options.stop_command, function()
		M.stop()
	end, { force = true, desc = "Stop watching the AI change file" })

	vim.keymap.set("n", options.keymap, function()
		M.run()
	end, { desc = "AI request in editor context" })

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

---Stop watching the change file.
M.stop = quickfix.stop

---@return table current merged options
M.get_config = config.get

return M
