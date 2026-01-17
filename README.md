# stride.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

> **Early Development**: This plugin is under active development. APIs and behavior may change between releases. Feedback and bug reports welcome!

AI-powered next-edit suggestions (NES) for Neovim. Stride predicts where you'll edit next based on your recent changes — rename a variable on line 10, and stride suggests updating line 50. Also supports inline ghost text completions.

Powered by the Cerebras API for ultra-low latency inference.

## Features

### Refactor Mode (Next-Edit Suggestions)
- **Next-edit prediction**: Rename `apple` to `orange` on line 1, and stride suggests updating line 20
- **Automatic trigger**: Predictions fire on `InsertLeave` and normal mode edits (`x`, `dd`, etc.)
- **Remote suggestions**: Highlights target text (strikethrough) with replacement shown inline
- **Insert detection**: Adds new parameters, properties, or arguments where needed
- **Incremental tracking**: Edits tracked in real-time via `nvim_buf_attach`
- **Esc to dismiss**: Press Esc in normal mode to clear suggestion
- **`:StrideClear`**: Clear all tracked changes manually

### Completion Mode
- Real-time ghost text completions as you type
- Treesitter-aware context capture for smarter completions
- Comment-intent completion: type `// log the id` and get `console.log(id)`
- Project context: include AGENTS.md rules in prompts
- Multi-line suggestions
- Tab to accept

### Core
- Automatic race condition handling
- Configurable debounce and filetypes
- **Gutter icon**: Shows indicator in sign column when suggestion is active
- **`:StrideEnable` / `:StrideDisable`**: Toggle predictions globally

## Requirements

- Neovim 0.10+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional, for smart context)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (optional, for animated notifications)
- Cerebras API key

## Installation

### lazy.nvim

```lua
{
  "your-username/nvim-stride",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter", -- optional, smart context
    "folke/snacks.nvim",               -- optional, animated notifications
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
    "nvim-treesitter/nvim-treesitter", -- optional, smart context
    "folke/snacks.nvim",               -- optional, animated notifications
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
  model = "gpt-oss-120b",

  -- UX Settings
  debounce_ms = 300,           -- Debounce for insert mode (ms)
  debounce_normal_ms = 500,    -- Debounce for normal mode edits (ms)
  accept_keymap = "<Tab>",     -- Key to accept suggestion
  context_lines = 30,          -- Lines of context before/after cursor

  -- Feature Flags
  use_treesitter = true,       -- Use Treesitter for smart context expansion
  disabled_filetypes = {},     -- Additional filetypes to disable (merged with defaults)
  disabled_buftypes = {},      -- Additional buftypes to disable (merged with defaults)
  debug = false,               -- Enable debug logging to file

  -- Mode Selection
  mode = "completion",         -- "completion", "refactor", or "both"
  show_remote = true,          -- Show remote suggestions in refactor mode

  -- Refactor Mode Settings
  max_tracked_changes = 10,    -- Max edits to track in history
  token_budget = 1000,         -- Max tokens for change history in prompt
  small_file_threshold = 200,  -- Files <= this many lines send whole content

  -- Project Context
  context_files = false,       -- false or {"AGENTS.md", ".cursor/rules"}

  -- Gutter Sign
  sign = {
    icon = nil,                -- nil = auto-detect nerd font ("󰷺" or ">")
    hl = "StrideSign",         -- Highlight group for sign
  },
  -- sign = false,             -- Set to false to disable gutter sign

  -- Notifications (bottom-center popup when suggestions available)
  notify = {
    enabled = true,            -- Show notifications
    timeout = 2000,            -- Display duration (ms)
    backend = "builtin",       -- "builtin" or "fidget"
  },
  -- notify = false,           -- Set to false to disable notifications
})
```

### Highlight Groups

Stride defines the following highlight groups with sensible defaults. To customize, define them **before** calling `setup()`:

```lua
-- Custom highlights (define before setup)
vim.api.nvim_set_hl(0, "StrideReplace", { fg = "#ff5555", strikethrough = true })
vim.api.nvim_set_hl(0, "StrideRemoteSuggestion", { fg = "#8be9fd", italic = true })
vim.api.nvim_set_hl(0, "StrideInsert", { fg = "#50fa7b", italic = true })
vim.api.nvim_set_hl(0, "StrideSign", { fg = "#50fa7b" })
vim.api.nvim_set_hl(0, "StrideNotify", { bg = "#1e1e2e" })
vim.api.nvim_set_hl(0, "StrideNotifyBorder", { fg = "#6c7086" })

require("stride").setup()
```

| Highlight Group | Purpose | Default |
|-----------------|---------|---------|
| `StrideReplace` | Text being replaced (strikethrough) | `DiagnosticError` fg, strikethrough |
| `StrideRemoteSuggestion` | Replacement text preview | `DiagnosticOk` fg, italic |
| `StrideInsert` | Insertion point marker | `DiagnosticOk` fg, italic |
| `StrideSign` | Gutter icon for active suggestions | `DiagnosticOk` fg |
| `StrideNotify` | Notification popup text | `NormalFloat` |
| `StrideNotifyBorder` | Notification popup border | `FloatBorder` |

## Usage

### Completion Mode (default)

1. Start typing in insert mode
2. After a brief pause (300ms default), a ghost text suggestion appears
3. Press `<Tab>` to accept the suggestion
4. Press any other key to dismiss and continue typing

### Refactor Mode

1. Enable refactor mode:
   ```lua
   require("stride").setup({ mode = "refactor" })
   -- or use both modes simultaneously:
   require("stride").setup({ mode = "both" })
   ```

2. Make an edit (e.g., rename a variable)
3. Exit insert mode — stride detects the change and predicts related edits
4. Remote suggestion appears: original text strikethrough in red, replacement shown at EOL in cyan
5. Press `<Tab>` to accept the edit
6. Press `<Esc>` to dismiss and continue editing
7. Use `:StrideClear` to reset tracked changes

### Global Toggle

- `:StrideEnable` — Enable predictions globally
- `:StrideDisable` — Disable predictions, clear UI, cancel pending requests

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

### Notifications

When refactor suggestions are available, stride shows a bottom-center notification:

```
󰷺 ↓ Tab to apply
```

The arrow indicates direction (↑ suggestion above cursor, ↓ below cursor).

**Animation**: If [snacks.nvim](https://github.com/folke/snacks.nvim) is installed, notifications fade in/out smoothly. Otherwise they appear/disappear instantly.

**Disable notifications**:
```lua
require("stride").setup({
  notify = false,
})
```

**Use fidget.nvim instead** (legacy):
```lua
require("stride").setup({
  notify = { backend = "fidget" },
})
```

## How It Works

### Completion Mode
1. **Debounced Trigger**: After you stop typing for 300ms, a prediction is requested
2. **Smart Context**: Uses Treesitter to capture full function/class definitions in context
3. **Ghost Text**: Suggestions appear as dimmed text after your cursor
4. **Race Protection**: Stale responses are discarded if you've moved the cursor

### Refactor Mode
1. **Incremental Tracking**: Edits tracked in real-time via `nvim_buf_attach` with `on_bytes` callback
2. **InsertLeave Trigger**: On leaving insert mode, stride analyzes recent edits
3. **Next-Edit Prediction**: LLM predicts related changes based on your edit patterns
4. **Remote Rendering**: Target text shown with strikethrough, replacement at EOL
5. **Accept or Dismiss**: Tab accepts, Esc dismisses in normal mode
6. **Token Budget**: Change history is trimmed to fit token budget for prompt
7. **Project Context**: If configured, AGENTS.md content is included in prompt for project-specific rules

## Plugin Structure

```
lua/
└── stride/
    ├── init.lua      # Public API, setup(), autocmds
    ├── config.lua    # User defaults, options merging
    ├── utils.lua     # Context extraction, Treesitter expansion
    ├── client.lua    # Cerebras API integration (completion)
    ├── ui.lua        # Ghost text rendering (local + remote)
    ├── history.lua   # Buffer snapshots, diff computation
    ├── predictor.lua # Next-edit prediction
    ├── notify.lua    # Bottom-center notifications
    ├── context.lua   # Project context (AGENTS.md) discovery
    └── log.lua       # Debug logging
```

## Roadmap

- [ ] LSP integration (diagnostics, symbols, go-to-definition context)
- [ ] Treesitter integration (semantic context, scope-aware predictions)
- [ ] Multi-file context awareness
- [ ] Custom prompt templates
- [ ] Prediction caching

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
