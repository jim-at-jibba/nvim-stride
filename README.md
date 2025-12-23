# stride.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

Ultra-low latency, multi-line code predictions ("Ghost Text") for Neovim using the Cerebras API.

## Features

- Real-time code completion suggestions as you type
- Treesitter-aware context capture for smarter completions
- Multi-line ghost text rendering
- Tab to accept suggestions
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
})
```

## Usage

1. Start typing in insert mode
2. After a brief pause (300ms default), a ghost text suggestion appears
3. Press `<Tab>` to accept the suggestion
4. Press any other key to dismiss and continue typing

## How It Works

1. **Debounced Trigger**: After you stop typing for 300ms, a prediction is requested
2. **Smart Context**: Uses Treesitter to capture full function/class definitions in context
3. **Ghost Text**: Suggestions appear as dimmed text after your cursor
4. **Race Protection**: Stale responses are discarded if you've moved the cursor

## Plugin Structure

```
lua/
└── stride/
    ├── init.lua      # Public API, setup(), autocmds
    ├── config.lua    # User defaults, options merging
    ├── utils.lua     # Context extraction, Treesitter expansion
    ├── client.lua    # Cerebras API integration
    └── ui.lua        # Ghost text rendering
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
