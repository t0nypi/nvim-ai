-- Headless integration test for nvim-ai.
-- Run with `make test` (or `bash tests/run.sh`).
local repo_root = assert(vim.env.REPO_ROOT, "REPO_ROOT is not set")
vim.opt.runtimepath:prepend(repo_root)

local function assert_eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg, vim.inspect(b), vim.inspect(a)))
	end
end

local function assert_true(v, msg)
	if not v then
		error("assertion failed: " .. msg)
	end
end

local plugin = require("nvim-ai")

-- setup must be idempotent
plugin.setup({})
plugin.setup({})
assert_eq(vim.fn.exists(":AIContext"), 2, "AIContext command")
assert_eq(vim.fn.exists(":AIContextStop"), 2, "AIContextStop command")
assert_eq(plugin.get_config().cmd, "pi", "default cmd")

-- mocks ---------------------------------------------------------------------
local real_system = vim.fn.system
local captured = {}
vim.fn.system = function(args)
	if type(args) == "table" and args[1] == "tmux" then
		captured[#captured + 1] = args
		real_system({ "true" }) -- reset vim.v.shell_error to 0
		return ""
	end
	return real_system(args)
end
vim.fn.input = function()
	return "rename this function"
end
vim.fn.confirm = function()
	return 1
end
vim.env.TMUX = "fake,1,0"

-- run -----------------------------------------------------------------------
local cwd = vim.fn.getcwd()
vim.api.nvim_win_set_cursor(0, { 1, 0 })

plugin.run()

assert_eq(#captured, 1, "one tmux invocation")
local tmux_args = captured[1]
assert_eq(tmux_args[1], "tmux", "tmux argv[1]")
assert_eq(tmux_args[2], "split-window", "tmux argv[2]")
assert_eq(tmux_args[3], "-h", "tmux argv[3]")
assert_eq(tmux_args[4], "-c", "tmux argv[4]")
assert_eq(tmux_args[5], cwd, "tmux cwd")

local cmd = tmux_args[6]
assert_true(cmd:match("pi") ~= nil, "command invokes pi")
assert_true(cmd:match("%-%-append%-system%-prompt") ~= nil, "has --append-system-prompt")
assert_true(cmd:match("rename this function") ~= nil, "carries the user request")

local prompt_file = cmd:match("'([^']*%.md)'")
assert_true(prompt_file ~= nil, "prompt file path found in command")
local prompt_text = table.concat(vim.fn.readfile(prompt_file), "\n")
assert_true(prompt_text:match(vim.pesc(cwd .. "/prova.lua")) ~= nil, "prompt has file path")
assert_true(prompt_text:match("at line `1`") ~= nil, "prompt has cursor line")
for _, phrase in ipairs({
	"same session across multiple rounds",
	"rewrite that file from scratch",
	"first round plus any later adjustments",
	"replaced or reverted",
	"complete and current picture",
	"%.currentChange",
}) do
	assert_true(prompt_text:match(phrase) ~= nil, "prompt missing phrase: " .. phrase)
end
print("OK: spawn command + system prompt")

-- change file was reset
local change_path = cwd .. "/.currentChange"
assert_eq(vim.fn.filereadable(change_path), 1, ".currentChange created")
assert_eq(#vim.fn.readfile(change_path), 0, ".currentChange reset to empty")

-- watcher parses matching lines and ignores noise
vim.fn.writefile({
	cwd .. "/prova.lua:2:1 - first change",
	"# a stray comment that must be ignored",
	cwd .. "/prova.lua:4:2 - second change",
}, change_path)

local ok = vim.wait(3000, function()
	return #vim.fn.getqflist() == 2
end, 100)
assert_true(ok, "quickfix populated with 2 entries")
local items = vim.fn.getqflist()
assert_eq(items[1].lnum, 2, "first lnum")
assert_eq(items[1].col, 1, "first col")
assert_eq(items[1].text, "first change", "first text")
assert_eq(items[2].lnum, 4, "second lnum")
assert_eq(items[2].col, 2, "second col")
print("OK: quickfix parsed from .currentChange (" .. #items .. " entries)")

-- emptying the file clears the list
vim.fn.writefile({}, change_path)
local cleared = vim.wait(3000, function()
	return #vim.fn.getqflist() == 0
end, 100)
assert_true(cleared, "quickfix cleared when file emptied")
print("OK: quickfix cleared on empty file")

plugin.stop()
print("ALL TESTS PASSED")
vim.cmd("qa!")
