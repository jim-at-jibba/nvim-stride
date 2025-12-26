# Completion Mode

Real-time, multi-line code completion suggestions as you type.

## Overview

Completion mode provides "ghost text" predictions that appear inline after your cursor. The LLM analyzes your current context and suggests what comes next.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    User types in buffer                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  TextChangedI event fires                                    │
│  - Clear existing suggestion                                 │
│  - Cancel any in-flight request                              │
│  - Start debounce timer (300ms default)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (after debounce)
┌─────────────────────────────────────────────────────────────┐
│  Context Capture                                             │
│  - Grab lines before/after cursor (60 lines default)        │
│  - Treesitter expansion: include full function/class defs   │
│  - Split into prefix (before cursor) and suffix (after)     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  API Request                                                 │
│  - Send context to Cerebras API                              │
│  - Track cursor position for race condition check            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Response Handling                                           │
│  - Discard if cursor moved (stale response)                  │
│  - Filter echo responses (LLM repeating input)               │
│  - Strip markdown fences if present                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Render Ghost Text                                           │
│  - First line: inline virtual text after cursor              │
│  - Additional lines: virtual lines below                     │
│  - Styled as Comment (dimmed)                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  User Action                                                 │
│  - Tab: Accept suggestion, insert text, move cursor          │
│  - Any other key: Dismiss, continue typing                   │
│  - CursorMovedI/InsertLeave: Clear suggestion                │
└─────────────────────────────────────────────────────────────┘
```

## Trigger Conditions

Predictions trigger on `TextChangedI` (text changed in insert mode) after:
1. Debounce period expires (300ms default)
2. Cursor hasn't moved since typing stopped
3. Current filetype is not disabled

## Context Capture

### Basic Context

By default, stride captures lines around the cursor:

```
Lines 1-40:   [prefix context]
Line 41:      function calculate(|  ← cursor here
Lines 42-100: [suffix context]
```

The `context_lines` setting controls how many lines to capture (default: 60).

### Treesitter Expansion

When `use_treesitter = true`, stride intelligently expands context boundaries:

**Problem**: Naive line-based context might cut a function in half:

```lua
-- Line 20 (outside context window)
function helper(a, b, c)
  -- complex logic
end

-- Line 80 (inside context window)
local result = helper(  -- LLM doesn't know helper's signature!
```

**Solution**: Stride checks if context boundaries intersect a function/class definition and expands to include the full block:

```lua
-- Now included in context:
function helper(a, b, c)
  -- complex logic
end

-- LLM understands the function signature
local result = helper(x, y, z)
```

Expansion is limited to 50 additional lines to prevent excessive context.

## Ghost Text Rendering

Suggestions render using Neovim extmarks:

```lua
local function greet(name)
  return "Hello, " .. name|.. "!"  -- dimmed ghost text
end                        |
                           └─ cursor position
```

Multi-line suggestions use virtual lines:

```lua
local function process(data)
  |for _, item in ipairs(data) do  -- line 1: inline
    table.insert(results, item)    -- line 2+: virtual lines
  end
  return results
```

## Accepting Suggestions

Press `<Tab>` (configurable) to accept:

1. First line is inserted at cursor position
2. Additional lines are inserted below
3. Cursor moves to end of inserted text
4. Ghost text is cleared

## Race Condition Protection

Multiple safeguards prevent stale suggestions:

1. **Request Cancellation**: New typing cancels in-flight requests
2. **Cursor Check**: Response discarded if cursor moved since request
3. **Buffer Check**: Response discarded if buffer changed
4. **Echo Detection**: Filters responses that just repeat the input

## Configuration

```lua
require("stride").setup({
  mode = "completion",      -- Enable completion mode (default)
  
  -- Trigger settings
  debounce_ms = 300,        -- Wait before triggering
  context_lines = 60,       -- Lines of context
  
  -- Smart context
  use_treesitter = true,    -- Expand to full function/class defs
  
  -- Keymaps
  accept_keymap = "<Tab>",  -- Key to accept suggestion
})
```

## Disabling for Filetypes

```lua
require("stride").setup({
  disabled_filetypes = { "markdown", "text", "help" },
})
```

## Integration with Other Plugins

### blink.cmp

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

### nvim-cmp

Use a different keymap to avoid conflicts:

```lua
require("stride").setup({
  accept_keymap = "<C-y>",
})
```

## Modules Involved

| Module | Role |
|--------|------|
| `init.lua` | Setup autocmds, keymaps, public API |
| `config.lua` | User options |
| `utils.lua` | Context capture, Treesitter expansion |
| `client.lua` | API requests, response handling |
| `ui.lua` | Ghost text rendering |
