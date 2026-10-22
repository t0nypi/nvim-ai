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

local function file_contains(path, needle, msg)
	local text = table.concat(vim.fn.readfile(path), "\n")
	assert_true(text:match(vim.pesc(needle)) ~= nil, msg .. " (missing " .. needle .. ")")
end

local plugin = require("nvim-ai")
local config = require("nvim-ai.config")
local session = require("nvim-ai.session")
local prompt = require("nvim-ai.prompt")

-- setup must be idempotent
plugin.setup({})
plugin.setup({})
assert_eq(vim.fn.exists(":AIContext"), 2, "AIContext command")
assert_eq(vim.fn.exists(":AIContextContinue"), 2, "AIContextContinue command")
assert_eq(vim.fn.exists(":AIContextStop"), 2, "AIContextStop command")
assert_eq(plugin.get_config().cmd, "pi", "default cmd")
print("OK: commands registered")

-- isolate sessions under a temporary root
local session_root = vim.fn.tempname() .. "-sessions"
vim.fn.mkdir(session_root, "p")
plugin.setup({ session_dir = session_root })
assert_eq(config.get().session_dir, session_root, "session_dir override")

-- mocks ---------------------------------------------------------------------
local real_system = vim.fn.system
local captured = {}
local tmux_handler
local last_pasted
vim.fn.system = function(args)
	if type(args) == "table" and args[1] == "tmux" then
		captured[#captured + 1] = args
		real_system({ "true" }) -- reset vim.v.shell_error to 0
		if tmux_handler then
			local out = tmux_handler(args)
			if out ~= nil then
				return out
			end
		end
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

local function find_capture(subcommand)
	for _, args in ipairs(captured) do
		if args[2] == subcommand then
			return args
		end
	end
	return nil
end

local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()

---Fill the scratch request buffer and save it, as the user would.
local function submit_request(text)
	local buf = vim.fn.bufnr("AI request")
	assert_true(buf ~= -1, "AI request buffer exists")
	local ai_win = vim.api.nvim_get_current_win()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	vim.api.nvim_set_current_buf(buf)
	vim.cmd("write")
	vim.wait(300)
	if vim.api.nvim_win_is_valid(ai_win) and ai_win ~= source_win then
		pcall(vim.api.nvim_win_close, ai_win, true)
	end
	vim.api.nvim_set_current_win(source_win)
	vim.api.nvim_win_set_buf(source_win, source_buf)
end

-- run -----------------------------------------------------------------------
local cwd = vim.fn.getcwd()
vim.api.nvim_win_set_cursor(0, { 1, 0 })

plugin.run()
submit_request("rename this function")

local split_args = find_capture("split-window")
assert_true(split_args ~= nil, "one tmux split-window invocation")
assert_eq(split_args[1], "tmux", "tmux argv[1]")
assert_eq(split_args[2], "split-window", "tmux argv[2]")
assert_eq(split_args[3], "-h", "tmux argv[3]")
assert_eq(split_args[4], "-c", "tmux argv[4]")
assert_eq(split_args[5], cwd, "tmux cwd")

local cmd = split_args[#split_args]
assert_true(cmd:match("pi") ~= nil, "command invokes pi")
assert_true(cmd:match("%-%-append%-system%-prompt") ~= nil, "has --append-system-prompt")
assert_true(cmd:match("%-%-session%-id") ~= nil, "has --session-id")
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

local generated_id = cmd:match("'%-%-session%-id'%s+'([^']+)'")
assert_true(generated_id ~= nil, "session id found in command")
assert_true(generated_id:match("^nvim%-ai%-%d+%-%x%x%x%x$") ~= nil, "generated id shape")
assert_eq(vim.g.PI_LATEST_SESSION, generated_id, "latest session recorded")

local title_args = find_capture("select-pane")
assert_true(title_args ~= nil and title_args[#title_args] == generated_id, "pane titled with session id")
local option_args = find_capture("set-option")
assert_true(
	option_args ~= nil and option_args[#option_args] == generated_id,
	"pane user option holds session id"
)
print("OK: spawn command + system prompt + session identity")

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

-- visual selection context --------------------------------------------------
captured = {}
plugin.run({ range = { srow = 2, scol = 3, erow = 4, ecol = 5, mode = "v" } })
submit_request("visual request")
local visual_split = find_capture("split-window")
local visual_prompt_file = visual_split[#visual_split]:match("'([^']*%.md)'")
local visual_prompt = table.concat(vim.fn.readfile(visual_prompt_file), "\n")
assert_true(
	visual_prompt:match("selection from line `2`, column `3` to line `4`, column `5`") ~= nil,
	"visual prompt has charwise selection range"
)
print("OK: visual charwise selection context")

captured = {}
plugin.run({ range = { srow = 3, scol = 1, erow = 5, ecol = 1, mode = "V" } })
submit_request("linewise request")
local linewise_split = find_capture("split-window")
local linewise_prompt_file = linewise_split[#linewise_split]:match("'([^']*%.md)'")
local linewise_prompt = table.concat(vim.fn.readfile(linewise_prompt_file), "\n")
assert_true(
	linewise_prompt:match("specifically lines `3` to `5`") ~= nil,
	"visual prompt has linewise selection range"
)
print("OK: visual linewise selection context")

-- selection range capture ---------------------------------------------------
local selection = require("nvim-ai.selection")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aaaa", "bbbb", "cccc", "dddd" })
vim.api.nvim_win_set_cursor(0, { 2, 1 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("vj", true, false, true), "x", false)
local charwise = selection.range()
assert_eq(charwise.srow, 2, "charwise srow")
assert_eq(charwise.scol, 2, "charwise scol")
assert_eq(charwise.erow, 3, "charwise erow")
assert_eq(charwise.ecol, 2, "charwise ecol")
assert_eq(charwise.mode, "v", "charwise mode")
vim.cmd("normal! \27")
print("OK: selection range capture (charwise)")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Vj", true, false, true), "x", false)
local linewise = selection.range()
assert_eq(linewise.srow, 1, "linewise srow")
assert_eq(linewise.erow, 2, "linewise erow")
assert_eq(linewise.mode, "V", "linewise mode")
vim.cmd("normal! \27")
print("OK: selection range capture (linewise)")

-- session identity and discovery -------------------------------------------
local id = session.generate_id()
assert_true(id:match("^nvim%-ai%-%d+%-%x%x%x%x$") ~= nil, "id format")
assert_true(id:match("^[A-Za-z0-9._-]+$") ~= nil, "id uses pi's allowed charset")

local expected_dir = session_root
	.. "/--"
	.. cwd:gsub("^[/\\]", ""):gsub("[/\\:]", "-")
	.. "--"
assert_eq(session.dir_for(cwd), expected_dir, "session dir encoding")

vim.fn.mkdir(session.dir_for(cwd), "p")
local function write_session(name, id_value, cwd_value, mtime)
	local path = session.dir_for(cwd) .. "/" .. name .. "_" .. id_value .. ".jsonl"
	vim.fn.writefile({
		vim.json.encode({ type = "session", id = id_value, cwd = cwd_value }),
	}, path)
	if mtime then
		vim.uv.fs_utime(path, mtime, mtime)
	end
	return path
end

local old_path = write_session("1000", "nvim-ai-1000-aaaa", cwd, os.time() - 1000)
local new_path = write_session("2000", "nvim-ai-2000-bbbb", cwd, os.time())
assert_eq(session.path_for_id(cwd, "nvim-ai-1000-aaaa"), old_path, "path_for_id")
local newest = session.latest(cwd)
assert_true(newest ~= nil, "latest found")
assert_eq(newest.id, "nvim-ai-2000-bbbb", "latest picks newest mtime")
assert_eq(newest.path, new_path, "latest path")

session.record(cwd, "nvim-ai-1000-aaaa")
local preferred = session.resolve(cwd)
assert_eq(preferred.id, "nvim-ai-1000-aaaa", "resolve prefers recorded id")
assert_eq(preferred.path, old_path, "resolve recorded path")
print("OK: session id, encoding, latest and recorded resolution")

-- prefill text ---------------------------------------------------------------
local prefill_normal = prompt.build_prefill({
	file = cwd .. "/prova.lua",
	display_file = "prova.lua",
	line = 7,
})
assert_eq(
	prefill_normal,
	"Now, with particular focus on file: prova.lua, at line: 7, satisfy the following request:",
	"normal prefill"
)
local prefill_v = prompt.build_prefill({
	file = cwd .. "/prova.lua",
	display_file = "prova.lua",
	range = { srow = 2, scol = 3, erow = 4, ecol = 5, mode = "v" },
})
assert_eq(
	prefill_v,
	"Now, with particular focus on file: prova.lua, in range: 2:3-4:5, satisfy the following request:",
	"charwise prefill"
)
local prefill_V = prompt.build_prefill({
	file = cwd .. "/prova.lua",
	display_file = "prova.lua",
	range = { srow = 3, scol = 1, erow = 5, ecol = 1, mode = "V" },
})
assert_eq(
	prefill_V,
	"Now, with particular focus on file: prova.lua, in range: 3-5, satisfy the following request:",
	"linewise prefill"
)
print("OK: prefill text")

-- Case A: session already running in a pane --------------------------------
session.record(cwd, "nvim-ai-1000-aaaa")
vim.fn.writefile({ cwd .. "/prova.lua:2:1 - keep me" }, change_path)
captured = {}
last_pasted = nil
tmux_handler = function(args)
	if args[2] == "list-panes" then
		return "%1\t" .. "nvim-ai-1000-aaaa" .. "\tnvim-ai-1000-aaaa\n"
	end
	if args[2] == "load-buffer" then
		last_pasted = table.concat(vim.fn.readfile(args[#args]), "\n")
	end
	return nil
end
vim.api.nvim_win_set_cursor(0, { 2, 0 })
plugin.run_continue()

assert_true(find_capture("split-window") == nil, "Case A does not split")
local select_args = find_capture("select-pane")
assert_true(select_args ~= nil and select_args[4] == "%1", "Case A selects the pane")
local paste_args = find_capture("paste-buffer")
assert_true(paste_args ~= nil, "Case A pastes into the pane")
assert_true(vim.tbl_contains(paste_args, "-p"), "Case A uses bracketed paste")
assert_true(find_capture("delete-buffer") ~= nil, "Case A deletes the buffer")
assert_true(last_pasted:match("at line: 2") ~= nil, "Case A prefill has line")
assert_true(last_pasted:match("prova.lua") ~= nil, "Case A prefill uses relative path")
assert_true(last_pasted:sub(-1) ~= "\n", "Case A prefill has no trailing newline")
assert_eq(
	table.concat(vim.fn.readfile(change_path), "\n"),
	cwd .. "/prova.lua:2:1 - keep me",
	"Case A leaves .currentChange untouched"
)
print("OK: Case A focuses existing pane and pastes prefill")

-- Case B: resume in a new pane ---------------------------------------------
captured = {}
tmux_handler = function(args)
	if args[2] == "list-panes" then
		return "%9\tother\tother\n"
	end
	return nil
end
vim.fn.writefile({ "keep" }, change_path)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
plugin.run_continue()

local resume_split = find_capture("split-window")
assert_true(resume_split ~= nil, "Case B splits a pane")
local resume_cmd = resume_split[#resume_split]
assert_true(resume_cmd:match("'%-%-session%-id'%s+'nvim%-ai%-1000%-aaaa'") ~= nil, "Case B resumes by id")
assert_true(resume_cmd:match("'-e'%s+'[^']*nvim%-ai%-prefill%.ts'") ~= nil, "Case B loads extension")
assert_true(resume_cmd:match("'%-%-nvim%-ai%-prefill%-file'") ~= nil, "Case B passes prefill flag")
assert_true(resume_cmd:match("%-%-append%-system%-prompt") ~= nil, "Case B keeps contract prompt")
assert_true(resume_cmd:match("'%-%-'") == nil, "Case B has no request positional")
local resume_prefill_file = resume_cmd:match("'%-%-nvim%-ai%-prefill%-file'%s+'([^']+)'")
assert_true(resume_prefill_file ~= nil, "Case B prefill file path")
file_contains(resume_prefill_file, "Now, with particular focus on file: prova.lua, at line: 1", "prefill file")
local resume_title = find_capture("select-pane")
assert_true(resume_title ~= nil and resume_title[#resume_title] == "nvim-ai-1000-aaaa", "Case B titles pane")
local resume_option = find_capture("set-option")
assert_true(
	resume_option ~= nil and resume_option[#resume_option] == "nvim-ai-1000-aaaa",
	"Case B tags pane"
)
assert_eq(vim.g.PI_LATEST_SESSION, "nvim-ai-1000-aaaa", "Case B records latest session")
assert_eq(table.concat(vim.fn.readfile(change_path), "\n"), "keep", "Case B leaves .currentChange untouched")
print("OK: Case B resumes in a new pane with prefill extension")

plugin.stop()
print("ALL TESTS PASSED")
vim.cmd("qa!")
