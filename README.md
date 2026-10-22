# nvim-ai

Editor-contextualized AI agent for Neovim.

`nvim-ai` turns the position you invoked it from into context for an
interactive coding agent, runs that agent in a **tmux split pane**, and mirrors
the agent's change list into Neovim's **quickfix list** so you can walk through
every change in order.

It was built around [`pi`](https://github.com/earendil-works/pi) but the agent
command is configurable.

## Features

- **Context-aware prompt** — appends a system prompt telling the agent which
  file and line you invoked it from, or the start/end position of the visual
  selection when you invoke it from visual mode.
- **Inline rationale** — asks the agent to comment each change it makes and to
  report broader notes in the session summary.
- **Reviewable changes** — the agent writes `filepath:line:col - summary`
  entries to `.currentChange`; these are parsed into the quickfix list and kept
  up to date as the session continues.
- **Cumulative across rounds** — `.currentChange` always describes the whole
  session (first round + later adjustments − reverted changes), not just the
  latest round.
- **Clean working tree** — saves the buffer first and warns about unstaged
  changes before launching (opening fugitive if you decline).
- **Continue a session** — `:AIContextContinue` resumes the newest pi session
  for the current directory, prefilling the agent editor with the current
  file/line (or selection) so you only type the request.

## Requirements

- Neovim >= 0.10
- An agent CLI. Defaults to [`pi`](https://github.com/earendil-works/pi).
- `tmux` — optional; falls back to a Neovim terminal split.
- `git` + [vim-fugitive](https://github.com/tpope/vim-fugitive) — optional,
  used to review unstaged changes.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-user/nvim-ai",
  opts = {},
  -- Optional: lazy-load on the mapping/command.
  keys = {
    { "<leader>ai", desc = "AI request in editor context" },
    { "<leader>ac", desc = "Continue the latest AI session" },
  },
  cmd = { "AIContext", "AIContextContinue", "AIContextStop" },
}
```

The `opts` table is passed to `require("nvim-ai").setup(opts)`.

For local development, point lazy at the checkout:

```lua
{
  dir = "~/playground/nvim-ai",
  opts = {},
}
```

## Usage

| Command | Description |
| --- | --- |
| `:AIContext` | Ask for a request and launch the contextual agent. |
| `:AIContextContinue` | Continue the latest session for this cwd, with the editor prefilled. |
| `:AIContextStop` | Stop watching the change file. |

Default mappings: `<leader>ai` starts a new session and `<leader>ac` continues
the latest one. Both work in visual mode: the selection is captured and the
context describes its start/end position instead of the cursor line.

The `:AIContext` flow:

1. Prompts `AI request:` in the command line.
2. Saves the current buffer.
3. If the repository has unstaged changes, warns and asks to proceed; on "No"
   it opens fugitive so you can review them.
4. Launches the agent in a tmux split pane with an appended system prompt
   carrying the file/line context and the change-reporting contract.
5. Polls `<cwd>/.currentChange` and parses matching lines into the quickfix
   list.

The `:AIContextContinue` flow:

1. Saves the current buffer.
2. Resolves the newest pi session for this cwd (recorded id first, then the
   newest session file on disk).
3. If that session is already running in a pane in the current tmux window, it
   focuses the pane and pastes a prefill sentence (not submitted) describing the
   file/line or selection.
4. Otherwise it splits a pane, resumes the session with `--session-id`, and a
   bundled pi extension prefills the editor with the same sentence.
5. Refreshes the quickfix watcher without clearing `.currentChange`, since the
   same session keeps updating it.

If no session exists yet, run `:AIContext` first.

## Configuration

```lua
require("nvim-ai").setup({
  -- Commands / mapping.
  command = "AIContext",
  stop_command = "AIContextStop",
  keymap = "<leader>ai",
  -- Visual-mode mapping. When nil it falls back to `keymap`; false disables it.
  visual_keymap = nil,

  -- Continue commands/mappings (visual falls back to continue_keymap).
  continue_command = "AIContextContinue",
  continue_keymap = "<leader>ac",
  continue_visual_keymap = nil,

  -- Session discovery. session_dir overrides $PI_CODING_AGENT_SESSION_DIR
  -- (which overrides ~/.pi/agent/sessions).
  session_id_prefix = "nvim-ai",
  session_dir = nil,
  -- Search every tmux window for the running session pane, not just this one.
  pane_search_all_windows = false,
  -- Bundled extension used to prefill pi's editor when resuming.
  prefill_extension = "<plugin-root>/pi/nvim-ai-prefill.ts",
  prefill_flag = "--nvim-ai-prefill-file",

  -- Agent executable and extra args (inserted before the append flag).
  cmd = "pi",
  extra_args = {},
  append_system_prompt_flag = "--append-system-prompt",

  -- Change file, relative to Neovim's cwd.
  change_file = ".currentChange",

  -- tmux split: "-h" side-by-side, "-v" stacked.
  split = "-h",
  -- true => keep focus in Neovim (adds -d to tmux split-window).
  detach = false,
  tmux = "tmux",

  -- Polling interval (ms) for the change file.
  poll_interval = 500,
  -- Auto-open the quickfix window when the list is (re)populated.
  open_quickfix = false,
  -- errorformat used to parse the change file.
  errorformat = "%f:%l:%c - %m",
})
```

### The change file

The agent is instructed to keep `<cwd>/.currentChange` up to date, one entry per
line:

```
/path/to/file.lua:12:3 - rename helper and update call sites
/path/to/file.lua:40:1 - add nil guard
```

Each line becomes a quickfix entry, so `:copen` (or `:cnext`) lets you jump
through the changes. Emptying the file clears the quickfix list. Add
`.currentChange` to your global/local git excludes if you do not want it
showing up as untracked.

### Session lookup caveats

- Pane lookup is scoped to the current tmux window by default. If the session
  runs in another window, `:AIContextContinue` starts a second pi on the same
  session file; set `pane_search_all_windows = true` to widen the search.
- Panes are tagged with the session id both as their title and as the
  `@nvim_ai_session` user option. The option is the primary key because a
  program can overwrite a pane title via OSC.
- Session directory encoding depends on pi and Neovim agreeing on the cwd. tmux
  panes are launched with `-c <cwd>`, so they do.

## API

```lua
local ai = require("nvim-ai")

ai.setup({ ... })    -- configure + register commands/keymap
ai.run()             -- launch a request programmatically
ai.run_continue()    -- continue the latest session programmatically
ai.stop()            -- stop watching the change file
ai.get_config()      -- current merged options
```

## Development

The repository is itself the plugin, and `.nvim.lua` is a dev shim that loads
it from the checkout via `exrc`.

```sh
make test   # headless integration test (tests/integration.lua)
```

## License

No license has been chosen yet.
