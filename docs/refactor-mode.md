# Refactor Mode

Next-edit prediction that suggests related changes after you make an edit.

## Overview

Refactor mode tracks your edits in real-time and predicts what else needs to change. Rename a variable on line 1, and stride suggests updating the same variable on line 50.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Buffer attached                           │
│  nvim_buf_attach with on_bytes callback                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  User edits in insert mode                                   │
│  - on_bytes captures: position, old text, new text           │
│  - Changes accumulated in History module                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  InsertLeave event fires                                     │
│  - Debounce timer starts (300ms default)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (after debounce)
┌─────────────────────────────────────────────────────────────┐
│  Predictor analyzes recent changes                           │
│  - Build unified diff of changes                             │
│  - Capture current buffer state                              │
│  - Construct prompt with change history                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  LLM Request                                                 │
│  - Send context + change history                             │
│  - Request: "What else needs to change?"                     │
│  - Response format: { find: "old", replace: "new" }          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Validate Response                                           │
│  - Verify "find" text exists in buffer                       │
│  - Must be outside recently edited lines                     │
│  - Must be a complete identifier (not partial match)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Render Remote Suggestion                                    │
│  - Strikethrough on target text (red)                        │
│  - Replacement shown at EOL (cyan)                           │
│  - Fidget notification (if available)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  User Action                                                 │
│  - Tab: Accept, apply edit, fetch next prediction            │
│  - Esc: Dismiss suggestion                                   │
│  - Any edit: Clear suggestion, start fresh                   │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Remote Suggestions

Unlike completion mode (inline ghost text), refactor mode shows "remote" suggestions - edits elsewhere in the file:

```typescript
// Line 5: You renamed userName → displayName
const displayName = user.name;

// Line 50: Stride suggests this change
console.log(userName);  →  displayName
            ~~~~~~~~
            strikethrough
```

### Change History Tracking

The History module tracks edits via `nvim_buf_attach`:

```lua
-- on_bytes callback receives:
{
  start_row = 5,
  start_col = 6,
  old_end_row = 5,
  old_end_col = 14,
  new_end_row = 5,
  new_end_col = 17,
}

-- History stores:
{
  old_text = "userName",
  new_text = "displayName",
  range = { start_line = 5, start_col = 6, ... },
  timestamp = 1703520000,
}
```

### Token Budget

Change history is trimmed to fit within the token budget:

```lua
-- Config
token_budget = 1000  -- Max tokens for change context

-- Oldest changes are dropped first
-- Recent changes are prioritized
```

### Unified Diff Format

Changes are sent to the LLM as unified diffs:

```diff
@@ -5,1 +5,1 @@
-const userName = user.name;
+const displayName = user.name;
```

## Remote Suggestion Rendering

### Visual Elements

```
Line 50: console.log(userName);  → displayName
                      ~~~~~~~~     ~~~~~~~~~~~~
                      │            │
                      │            └─ Replacement (cyan, StrideRemoteSuggestion)
                      └─ Original (strikethrough, StrideRemoteStrike)
```

### Highlight Groups

| Group | Default | Purpose |
|-------|---------|---------|
| `StrideRemoteStrike` | Red + strikethrough | Target text to replace |
| `StrideRemoteSuggestion` | Cyan | Replacement text at EOL |

Customize in your config:

```lua
vim.api.nvim_set_hl(0, "StrideRemoteStrike", { fg = "#ff6b6b", strikethrough = true })
vim.api.nvim_set_hl(0, "StrideRemoteSuggestion", { fg = "#4ecdc4" })
```

## Accepting Suggestions

Press `<Tab>` to accept:

1. Original text is replaced with new text
2. Cursor jumps to the edit location
3. History is updated
4. Next prediction is fetched (if pattern continues)

## Dismissing Suggestions

Press `<Esc>` in normal mode:

1. Suggestion UI is cleared
2. Tracked changes remain (for future predictions)

Use `:StrideClear` to reset everything:

1. Clear suggestion UI
2. Clear change history
3. Reset buffer snapshot

## Validation Rules

Predictions are validated before display:

### 1. Text Must Exist

The "find" text must exist somewhere in the buffer.

### 2. Complete Identifier Match

Avoid partial matches:

```typescript
// Change: name → firstName
// ✓ Valid: user.name → user.firstName
// ✗ Invalid: userName → userFirstName (partial match inside identifier)
```

Stride checks word boundaries using pattern matching.

### 3. Outside Edited Lines

Suggestions must be on different lines than recent edits (user already changed those).

### 4. Single Occurrence Preferred

If "find" text appears multiple times, the closest to cursor is suggested.

## Configuration

```lua
require("stride").setup({
  mode = "refactor",        -- Enable refactor mode only
  -- or
  mode = "both",            -- Enable both modes
  
  -- Refactor settings
  show_remote = true,       -- Show remote suggestions
  max_tracked_changes = 10, -- Max edits to track
  token_budget = 1000,      -- Max tokens for change history
  small_file_threshold = 200, -- Files <= this send whole content
})
```

## Trigger Flow

### InsertLeave Trigger

```
Insert Mode                    Normal Mode
     │                              │
     │  User types "displayName"    │
     │  (was "userName")            │
     │                              │
     └──────── <Esc> ───────────────┤
                                    │
                                    ▼
                            InsertLeave fires
                                    │
                                    ▼
                            Debounce (300ms)
                                    │
                                    ▼
                            Predictor.fetch()
                                    │
                                    ▼
                            LLM returns suggestion
                                    │
                                    ▼
                            UI renders remote
```

### Continuous Prediction

After accepting a suggestion, stride immediately fetches the next prediction:

```
Tab → Apply Edit → Update History → Fetch Next → Render
                                          │
                                          └─ Repeats until no more suggestions
```

## Modules Involved

| Module | Role |
|--------|------|
| `init.lua` | Setup autocmds, keymaps, coordinate modules |
| `history.lua` | Track edits via on_bytes, store change history |
| `predictor.lua` | Build prompts, call LLM, validate responses |
| `ui.lua` | Render remote suggestions (strikethrough + EOL) |
| `config.lua` | User options |

## LLM Prompt Structure

```
System: You are a code refactoring assistant. Based on the user's recent
edits, predict what else needs to change. Respond with JSON:
{ "find": "text to find", "replace": "replacement text" }

User:
File: src/user.ts
Language: typescript

Recent changes:
@@ -5,1 +5,1 @@
-const userName = user.name;
+const displayName = user.name;

Current file content:
[full file or relevant section]

What related change is needed?
```

## Edge Cases

| Case | Behavior |
|------|----------|
| No changes tracked | Skip prediction |
| LLM returns invalid JSON | Discard, retry on next edit |
| "find" text not found | Discard suggestion |
| "find" matches edited line | Discard (already changed) |
| Multiple matches | Suggest closest to cursor |
| File too large | Use cursor-centered context window |
| Rate limited | Retry with exponential backoff |

## Debugging

Enable debug logging:

```lua
require("stride.log").set_level("debug")
```

View logs:

```
:messages
```

Or tail the log file:

```bash
tail -f ~/.local/state/nvim/stride.log
```

Key log points:
- `HISTORY: tracked change` - New edit captured
- `PREDICTOR: building prompt` - Constructing LLM request
- `PREDICTOR: response` - LLM returned suggestion
- `UI: rendering remote` - Displaying suggestion
