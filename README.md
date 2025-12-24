# stride.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

Ultra-low latency, multi-line code predictions ("Ghost Text") for Neovim using the Cerebras API.

## Features

### V1: Completion Mode (default)
- Real-time code completion suggestions as you type
- Treesitter-aware context capture for smarter completions
- Multi-line ghost text rendering
- Tab to accept suggestions

### V2: Refactor Mode
- **Next-edit prediction**: Rename `apple` to `orange` on line 1, and stride suggests updating line 20
- **Tab-tab-tab flow**: Chain edits across the file without leaving insert mode
- **Remote suggestions**: Highlights target text with replacement shown at end of line
- Automatic edit history tracking within insert sessions

### Core
- Automatic race condition handling
- Configurable debounce and filetypes

## Requirements

- Neovim 0.10+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional, for smart context)
- Cerebras API key

## Installation

### lazy.nvim

```lua
{
  "your-username/nvim-stride",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter", -- optional
  },
  config = function()
    require("stride").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "your-username/nvim-stride",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("stride").setup()
  end,
}
```

## Setup

### API Key

Set your Cerebras API key as an environment variable:

```bash
export CEREBRAS_API_KEY="your-api-key-here"
```

Or pass it directly in setup:

```lua
require("stride").setup({
  api_key = "your-api-key-here",
})
```

### Configuration

```lua
require("stride").setup({
  -- API Configuration
  api_key = os.getenv("CEREBRAS_API_KEY"),
  endpoint = "https://api.cerebras.ai/v1/chat/completions",
  model = "llama3.1-70b",

  -- UX Settings
  debounce_ms = 300,        -- Wait time before triggering prediction
  accept_keymap = "<Tab>",  -- Key to accept suggestion
  context_lines = 60,       -- Lines of context before/after cursor

  -- Feature Flags
  use_treesitter = true,    -- Use Treesitter for smart context expansion
  disabled_filetypes = {},  -- Filetypes to disable (e.g., {"markdown", "text"})

  -- Mode Selection (V1/V2)
  mode = "completion",      -- "completion" (V1), "refactor" (V2), or "both"
  show_remote = true,       -- Show remote suggestions in refactor mode
})
```

## Usage

### Completion Mode (V1 - default)

1. Start typing in insert mode
2. After a brief pause (300ms default), a ghost text suggestion appears
3. Press `<Tab>` to accept the suggestion
4. Press any other key to dismiss and continue typing

### Refactor Mode (V2)

1. Enable refactor mode:
   ```lua
   require("stride").setup({ mode = "refactor" })
   -- or use both modes simultaneously:
   require("stride").setup({ mode = "both" })
   ```

2. Make an edit (e.g., rename a variable)
3. Stride detects the change and predicts related edits elsewhere
4. Remote suggestion appears: original text highlighted in red, replacement shown at EOL in cyan
5. Press `<Tab>` to jump to target and apply the edit
6. Repeat — stride auto-triggers the next prediction ("tab-tab-tab" flow)
7. Press `<Esc>` to exit insert mode (clears history for next session)

### With blink.cmp

If you use [blink.cmp](https://github.com/saghen/blink.cmp), configure Tab to check for stride suggestions first:

```lua
{
  "saghen/blink.cmp",
  opts = {
    keymap = {
      ["<Tab>"] = {
        function(cmp)
          local ok, ui = pcall(require, "stride.ui")
          if ok and ui.current_suggestion then
            return require("stride").accept()
          end
          return cmp.select_next()
        end,
        "fallback",
      },
    },
  },
}
```

Or use a different keymap for stride to avoid conflicts:

```lua
require("stride").setup({
  accept_keymap = "<C-y>",  -- Use Ctrl+Y instead of Tab
})
```

## How It Works

### V1: Completion Mode
1. **Debounced Trigger**: After you stop typing for 300ms, a prediction is requested
2. **Smart Context**: Uses Treesitter to capture full function/class definitions in context
3. **Ghost Text**: Suggestions appear as dimmed text after your cursor
4. **Race Protection**: Stale responses are discarded if you've moved the cursor

### V2: Refactor Mode
1. **Snapshot**: Buffer state captured on `InsertEnter`
2. **Diff Detection**: On each keystroke, computes diff between snapshot and current buffer
3. **Next-Edit Prediction**: LLM analyzes your recent edits and suggests related changes
4. **Remote Rendering**: Target text highlighted with replacement shown at EOL
5. **Jump & Apply**: Tab accepts the edit and moves cursor to target location
6. **Chain Edits**: After accepting, auto-triggers next prediction for continuous flow
7. **Session Isolation**: History cleared on `InsertLeave` — each session starts fresh

## Plugin Structure

```
lua/
└── stride/
    ├── init.lua      # Public API, setup(), autocmds
    ├── config.lua    # User defaults, options merging
    ├── utils.lua     # Context extraction, Treesitter expansion
    ├── client.lua    # Cerebras API integration (V1 completion)
    ├── ui.lua        # Ghost text rendering (local + remote)
    ├── history.lua   # Buffer snapshots, diff computation (V2)
    ├── predictor.lua # Next-edit prediction (V2)
    └── log.lua       # Debug logging
```

## Development

### Run tests

```bash
make test
```

### Format code

```bash
stylua lua/
```

## License

MIT
