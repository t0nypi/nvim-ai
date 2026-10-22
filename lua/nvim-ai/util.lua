-- nvim-ai.util: small, dependency-free helpers.
local M = {}

---@param msg string
---@param level integer|nil
function M.notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "AI Context" })
end

---Read a file, returning nil when it cannot be opened.
---@param path string
---@return string|nil
function M.read_file(path)
	local fd = io.open(path, "r")
	if not fd then
		return nil
	end
	local content = fd:read("*a")
	fd:close()
	return content
end

---@param dir string
---@return string|nil root, nil when `dir` is not inside a git work tree
function M.git_root(dir)
	local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return vim.trim(out)
end

---True only for unstaged modifications to tracked files (working tree vs index).
---@param root string
---@return boolean
function M.has_unstaged_changes(root)
	vim.fn.system({ "git", "-C", root, "diff", "--quiet" })
	-- `git diff --quiet` exits 1 when there are differences.
	return vim.v.shell_error == 1
end

---Return `path` relative to `cwd` when it lives inside it, absolute otherwise.
---@param path string
---@param cwd string
---@return string
function M.relpath(path, cwd)
	local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	local base = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
	if #base > 1 and base:sub(-1) == "/" then
		base = base:sub(1, -2)
	end
	if abs == base then
		return "."
	end
	local prefix = base == "/" and "/" or (base .. "/")
	if abs:sub(1, #prefix) == prefix then
		return abs:sub(#prefix + 1)
	end
	return abs
end

---Shell-escape and join an argv list into a single command string.
---@param args string[]
---@return string
function M.shelljoin(args)
	local escaped = {}
	for _, arg in ipairs(args) do
		escaped[#escaped + 1] = vim.fn.shellescape(arg)
	end
	return table.concat(escaped, " ")
end

---Open fugitive, falling back to `git diff` when it is not installed.
function M.open_fugitive()
	if vim.fn.exists(":Git") == 2 then
		vim.cmd("vert Git")
		return
	end
	M.notify("fugitive not found; opening `git diff`", vim.log.levels.WARN)
	vim.cmd("vsplit")
	vim.fn.termopen("git diff")
	vim.cmd("startinsert")
end

return M
