-- nvim-ai.quickfix: watches the change file and mirrors it into the quickfix list.
local config = require("nvim-ai.config")
local util = require("nvim-ai.util")

local uv = vim.uv or vim.loop

local M = {}

M.timer = nil
M.last_content = nil

---Stop watching the change file.
function M.stop()
	if M.timer then
		M.timer:stop()
		if not M.timer:is_closing() then
			M.timer:close()
		end
		M.timer = nil
	end
end

---Parse change-file contents and replace the quickfix list.
---@param content string
---@return integer number of entries
local function update(content)
	local opts = config.get()
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
		efm = opts.errorformat,
		lines = filtered,
	})
	return #vim.fn.getqflist()
end

---Start polling `path` and mirroring it into the quickfix list.
---@param path string
function M.start(path)
	M.stop()
	M.last_content = "__uninitialized__"
	local opts = config.get()
	local timer = uv.new_timer()
	M.timer = timer
	timer:start(
		0,
		opts.poll_interval,
		vim.schedule_wrap(function()
			local content = util.read_file(path) or ""
			if content == M.last_content then
				return
			end
			M.last_content = content
			local count = update(content)
			if count and count > 0 then
				util.notify(string.format("%d AI change(s) — :copen to review", count))
				if opts.open_quickfix then
					vim.cmd("copen")
				end
			end
		end)
	)
end

return M
