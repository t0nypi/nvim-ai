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
  file and line you invoked it from.
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
  keys = { { "<leader>ac", desc = "AI request in editor context" } },
  cmd = { "AIContext", "AIContextStop" },
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
| `:AIContextStop` | Stop watching the change file. |

Default mapping: `<leader>ac`.

The flow:

1. Prompts `AI request:` in the command line.
2. Saves the current buffer.
3. If the repository has unstaged changes, warns and asks to proceed; on "No"
   it opens fugitive so you can review them.
4. Launches the agent in a tmux split pane with an appended system prompt
   carrying the file/line context and the change-reporting contract.
5. Polls `<cwd>/.currentChange` and parses matching lines into the quickfix
   list.

## Configuration

```lua
require("nvim-ai").setup({
  -- Commands / mapping.
  command = "AIContext",
  stop_command = "AIContextStop",
  keymap = "<leader>ac",

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

## API

```lua
local ai = require("nvim-ai")

ai.setup({ ... })  -- configure + register commands/keymap
ai.run()           -- launch a request programmatically
ai.stop()          -- stop watching the change file
ai.get_config()    -- current merged options
```

## Development

The repository is itself the plugin, and `.nvim.lua` is a dev shim that loads
it from the checkout via `exrc`.

```sh
make test   # headless integration test (tests/integration.lua)
```

## License

No license has been chosen yet.
