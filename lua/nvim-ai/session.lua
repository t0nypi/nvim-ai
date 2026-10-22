-- nvim-ai.session: pi session identity, discovery and latest-session tracking.
local config = require("nvim-ai.config")
local util = require("nvim-ai.util")

local M = {}

-- Seed once so generated ids stay unique across invocations in one Neovim.
math.randomseed(os.time() + math.floor((vim.uv or vim.loop).hrtime() % 100000))

---@return string root directory holding all encoded pi session directories
local function session_root()
	local opts = config.get()
	if opts.session_dir and opts.session_dir ~= "" then
		return opts.session_dir
	end
	local env = vim.env.PI_CODING_AGENT_SESSION_DIR
	if env and env ~= "" then
		return env
	end
	return vim.fs.joinpath(vim.fn.expand("~"), ".pi", "agent", "sessions")
end

---Normalize a directory to an absolute path without a trailing separator.
---@param dir string
---@return string
local function absolute_dir(dir)
	local abs = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
	if #abs > 1 and abs:sub(-1) == "/" then
		abs = abs:sub(1, -2)
	end
	return abs
end

---Replicate pi's cwd encoding: `--<cwd without leading sep, separators -> ->--`.
---@param cwd string
---@return string
function M.dir_for(cwd)
	local safe = absolute_dir(cwd):gsub("^[/\\]", ""):gsub("[/\\:]", "-")
	return vim.fs.joinpath(session_root(), "--" .. safe .. "--")
end

---Generate a new pi session id shaped `nvim-ai-<epoch>-<4hex>`.
---@return string
function M.generate_id()
	local prefix = config.get().session_id_prefix
	local hex = string.format("%04x", math.random(0, 0xffff))
	return string.format("%s-%d-%s", prefix, os.time(), hex)
end

---Decode a session id from a `.jsonl` file's header, falling back to its name.
---@param path string
---@return string|nil
function M.id_from_file(path)
	local content = util.read_file(path)
	if content then
		local first = content:match("^[^\n]*")
		if first and first ~= "" then
			local ok, header = pcall(vim.json.decode, first)
			if ok and type(header) == "table" and header.type == "session" and type(header.id) == "string" then
				return header.id
			end
		end
	end
	local name = vim.fs.basename(path)
	local id = name:match("_(.-)%.jsonl$")
	if id and id ~= "" then
		return id
	end
	return nil
end

---@param cwd string
---@param id string
---@return string|nil
function M.path_for_id(cwd, id)
	local dir = M.dir_for(cwd)
	local names = vim.fn.readdir(dir)
	if not names or #names == 0 then
		return nil
	end
	local suffix = "_" .. id .. ".jsonl"
	for _, name in ipairs(names) do
		if name:sub(-#suffix) == suffix then
			return vim.fs.joinpath(dir, name)
		end
	end
	-- Header scan as a fallback for files whose name does not encode the id.
	for _, name in ipairs(names) do
		if name:sub(-6) == ".jsonl" then
			local path = vim.fs.joinpath(dir, name)
			if M.id_from_file(path) == id then
				return path
			end
		end
	end
	return nil
end

---Find the newest session file for a cwd by mtime.
---@param cwd string
---@return { id: string, path: string }|nil
function M.latest(cwd)
	local dir = M.dir_for(cwd)
	local names = vim.fn.readdir(dir)
	if not names or #names == 0 then
		return nil
	end
	local newest_path, newest_mtime
	for _, name in ipairs(names) do
		if name:sub(-6) == ".jsonl" then
			local path = vim.fs.joinpath(dir, name)
			local stat = (vim.uv or vim.loop).fs_stat(path)
			if stat then
				if not newest_mtime or stat.mtime.sec > newest_mtime.sec
					or (stat.mtime.sec == newest_mtime.sec and stat.mtime.nsec > newest_mtime.nsec) then
					newest_path = path
					newest_mtime = stat.mtime
				end
			end
		end
	end
	if not newest_path then
		return nil
	end
	local id = M.id_from_file(newest_path)
	if not id then
		return nil
	end
	return { id = id, path = newest_path }
end

---Record the latest session id globally and per cwd.
---@param cwd string
---@param id string
function M.record(cwd, id)
	vim.g.PI_LATEST_SESSION = id
	local map = vim.g.PI_LATEST_SESSION_BY_CWD or {}
	map[absolute_dir(cwd)] = id
	vim.g.PI_LATEST_SESSION_BY_CWD = map
end

---@param cwd string
---@return string|nil
function M.recorded(cwd)
	local map = vim.g.PI_LATEST_SESSION_BY_CWD or {}
	local id = map[absolute_dir(cwd)]
	if not id then
		id = vim.g.PI_LATEST_SESSION
	end
	return id
end

---Resolve the session to continue: recorded fast path, then newest on disk.
---@param cwd string
---@return { id: string, path: string }|nil
function M.resolve(cwd)
	local recorded = M.recorded(cwd)
	if recorded then
		local path = M.path_for_id(cwd, recorded)
		if path then
			return { id = recorded, path = path }
		end
	end
	return M.latest(cwd)
end

return M
