# Configuration

Complete reference for all stride.nvim configuration options.

## Quick Start

```lua
require("stride").setup({
  -- Minimal config - just set your API key
  api_key = os.getenv("CEREBRAS_API_KEY"),
})
```

## Full Configuration

```lua
require("stride").setup({
  -- API Configuration
  api_key = os.getenv("CEREBRAS_API_KEY"),  -- Required
  endpoint = "https://api.cerebras.ai/v1/chat/completions",
  model = "gpt-oss-120b",

  -- Trigger Settings
  debounce_ms = 300,        -- Wait before triggering prediction
  context_lines = 30,       -- Lines of context before/after cursor

  -- Smart Context
  use_treesitter = true,    -- Expand context to include full functions/classes

  -- Mode Selection
  mode = "completion",      -- "completion", "refactor", or "both"
  show_remote = true,       -- Show remote suggestions in refactor mode

  -- Refactor Mode Settings
  max_tracked_changes = 10, -- Max edits to track in history
  token_budget = 1000,      -- Max tokens for change history in prompt
  small_file_threshold = 200, -- Files <= this many lines send whole content

  -- Keymaps
  accept_keymap = "<Tab>",  -- Key to accept suggestion

  -- Filetypes
  disabled_filetypes = {},  -- Filetypes to disable (e.g., {"markdown", "text"})

  -- Debug
  debug = false,            -- Enable debug logging
})
```

## Option Reference

### API Configuration

#### `api_key`

**Type:** `string`  
**Default:** `os.getenv("CEREBRAS_API_KEY")`

Your Cerebras API key. Can be set via environment variable or passed directly.

```lua
-- Via environment (recommended)
api_key = os.getenv("CEREBRAS_API_KEY"),

-- Direct (not recommended for version control)
api_key = "your-api-key-here",
```

#### `endpoint`

**Type:** `string`  
**Default:** `"https://api.cerebras.ai/v1/chat/completions"`

API endpoint URL. Only change if using a custom/proxy endpoint.

#### `model`

**Type:** `string`  
**Default:** `"gpt-oss-120b"`

Model to use for predictions. Available models depend on your Cerebras account.

---

### Trigger Settings

#### `debounce_ms`

**Type:** `number`  
**Default:** `300`

Milliseconds to wait after typing stops before triggering a prediction.

- Lower values = faster predictions, more API calls
- Higher values = fewer API calls, feels slower

```lua
debounce_ms = 200,  -- Faster, more aggressive
debounce_ms = 500,  -- Slower, fewer API calls
```

#### `context_lines`

**Type:** `number`  
**Default:** `30`

Number of lines to capture before and after cursor for context.

```lua
context_lines = 60,  -- More context, larger prompts
context_lines = 20,  -- Less context, faster requests
```

---

### Smart Context

#### `use_treesitter`

**Type:** `boolean`  
**Default:** `true`

When enabled, stride expands context boundaries to include complete function/class definitions, even if they start outside the `context_lines` window.

```lua
use_treesitter = true,   -- Smart expansion (recommended)
use_treesitter = false,  -- Fixed line-based context
```

Requires [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with a parser for your language.

---

### Mode Selection

#### `mode`

**Type:** `"completion" | "refactor" | "both"`  
**Default:** `"completion"`

Which prediction modes to enable.

| Mode | Description |
|------|-------------|
| `"completion"` | Ghost text completions in insert mode |
| `"refactor"` | Next-edit predictions after leaving insert mode |
| `"both"` | Both modes simultaneously |

```lua
mode = "completion",  -- Just completions (default)
mode = "refactor",    -- Just refactoring
mode = "both",        -- Both features
```

#### `show_remote`

**Type:** `boolean`  
**Default:** `true`

Show remote (strikethrough + replacement) suggestions in refactor mode. Disable to only track history without showing predictions.

---

### Refactor Mode Settings

#### `max_tracked_changes`

**Type:** `number`  
**Default:** `10`

Maximum number of edits to track in change history. Oldest changes are dropped first.

```lua
max_tracked_changes = 5,   -- Less history, faster
max_tracked_changes = 20,  -- More history, better patterns
```

#### `token_budget`

**Type:** `number`  
**Default:** `1000`

Maximum tokens (~3 characters each) to use for change history in the LLM prompt. Helps control prompt size and cost.

```lua
token_budget = 500,   -- Smaller prompts
token_budget = 2000,  -- More context for patterns
```

#### `small_file_threshold`

**Type:** `number`  
**Default:** `200`

Files with this many lines or fewer send their entire content to the LLM. Larger files use a cursor-centered context window.

```lua
small_file_threshold = 100,  -- More files use windowed context
small_file_threshold = 500,  -- More files send full content
```

---

### Keymaps

#### `accept_keymap`

**Type:** `string`  
**Default:** `"<Tab>"`

Keymap to accept the current suggestion.

```lua
accept_keymap = "<Tab>",    -- Default
accept_keymap = "<C-y>",    -- Ctrl+Y (avoid Tab conflicts)
accept_keymap = "<C-CR>",   -- Ctrl+Enter
```

---

### Filetypes

#### `disabled_filetypes`

**Type:** `string[]`  
**Default:** `{}`

List of filetypes where stride should be disabled.

```lua
disabled_filetypes = {
  "markdown",
  "text",
  "help",
  "gitcommit",
  "TelescopePrompt",
},
```

---

### Debug

#### `debug`

**Type:** `boolean`  
**Default:** `false`

Enable debug logging. Logs are written to `~/.local/state/nvim/stride.log`.

```lua
debug = true,  -- Enable debug output
```

View logs:

```vim
:messages
```

Or:

```bash
tail -f ~/.local/state/nvim/stride.log
```

---

## Commands

| Command | Description |
|---------|-------------|
| `:StrideEnable` | Enable predictions globally |
| `:StrideDisable` | Disable predictions, clear UI, cancel requests |
| `:StrideClear` | Clear change history and suggestions |

---

## Highlight Groups

Customize suggestion appearance:

```lua
-- Completion mode ghost text
vim.api.nvim_set_hl(0, "Comment", { fg = "#6c7086", italic = true })

-- Refactor mode remote suggestions
vim.api.nvim_set_hl(0, "StrideRemoteStrike", { 
  fg = "#ff6b6b", 
  strikethrough = true 
})
vim.api.nvim_set_hl(0, "StrideRemoteSuggestion", { 
  fg = "#4ecdc4" 
})
```

---

## Example Configurations

### Minimal

```lua
require("stride").setup()
```

### Performance-Focused

```lua
require("stride").setup({
  debounce_ms = 200,
  context_lines = 20,
  max_tracked_changes = 5,
  token_budget = 500,
})
```

### Full-Featured

```lua
require("stride").setup({
  mode = "both",
  debounce_ms = 300,
  context_lines = 60,
  use_treesitter = true,
  max_tracked_changes = 15,
  token_budget = 1500,
  disabled_filetypes = { "markdown", "text", "help" },
  debug = false,
})
```

### Avoid Tab Conflicts (blink.cmp/nvim-cmp)

```lua
require("stride").setup({
  accept_keymap = "<C-y>",
})
```

---

## Type Definitions

For Lua LSP support, stride exports type annotations:

```lua
---@class Stride.Config
---@field api_key? string
---@field endpoint? string
---@field model? string
---@field debounce_ms? number
---@field accept_keymap? string
---@field context_lines? number
---@field use_treesitter? boolean
---@field disabled_filetypes? string[]
---@field debug? boolean
---@field mode? "completion"|"refactor"|"both"
---@field show_remote? boolean
---@field max_tracked_changes? number
---@field token_budget? number
---@field small_file_threshold? number
```
