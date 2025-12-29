# Add Normal Mode Prediction Trigger

Trigger refactor predictions on normal mode edits (`x`, `dd`, `:s`, etc.) that don't fire `InsertLeave`.

## Background

- History tracking via `on_bytes` already captures ALL buffer changes
- Problem: predictions only trigger on `InsertLeave`, missing normal mode edits
- Solution: add `TextChanged` autocommand with separate debounce timer

## Tasks

### 1. `lua/stride/config.lua`

Add type annotation (~line 9):
```lua
---@field debounce_normal_ms? number Debounce delay for normal mode edits (default: 500)
```

Add default (~line 29, after `debounce_ms`):
```lua
debounce_normal_ms = 500,
```

### 2. `lua/stride/utils.lua`

Add timer variable (~line 14, after `M.timer`):
```lua
---@type uv_timer_t|nil
M.timer_normal = nil
```

Add function (~line 161, after `M.debounce`):
```lua
---Debounce for normal mode edits (separate timer)
---@param ms number Delay in milliseconds
---@param callback function Function to call after delay
function M.debounce_normal(ms, callback)
  if M.timer_normal then
    Log.debug("debounce_normal: cancelling previous timer")
    M.timer_normal:stop()
    M.timer_normal:close()
  end
  Log.debug("debounce_normal: scheduling callback in %dms", ms)
  M.timer_normal = vim.loop.new_timer()
  M.timer_normal:start(ms, 0, vim.schedule_wrap(callback))
end
```

### 3. `lua/stride/init.lua`

Add helper function (~line 53, near other helpers):
```lua
---Check if current state is from undo/redo (not at tip of undo tree)
---@return boolean
local function _is_undo_redo()
  local tree = vim.fn.undotree()
  return tree.seq_cur ~= tree.seq_last
end
```

Add autocommand (~line 196, after `InsertLeave` handler):
```lua
-- V2: Trigger refactor prediction on normal mode text changes (x, dd, etc.)
vim.api.nvim_create_autocmd("TextChanged", {
  group = augroup,
  callback = function()
    if _is_disabled() then
      return
    end

    if not _mode_has_refactor() then
      return
    end

    -- Skip undo/redo operations
    if _is_undo_redo() then
      return
    end

    -- Clear stale prediction immediately
    Ui.clear()
    Predictor.cancel()

    local buf = vim.api.nvim_get_current_buf()
    local cursor_pos = _get_cursor_pos()

    Utils.debounce_normal(Config.options.debounce_normal_ms, function()
      _trigger_refactor_prediction(buf, cursor_pos)
    end)
  end,
})
```

## Behavior Summary

| Action | Trigger | Debounce |
|--------|---------|----------|
| Insert mode edit → leave | `InsertLeave` | 300ms |
| Normal mode edit (`x`, `dd`, `:s`) | `TextChanged` | 500ms |
| Undo/redo (`u`, `<C-r>`) | Skipped | — |

## Undo/Redo Detection

Uses `vim.fn.undotree()`:
- After new edit: `seq_cur == seq_last` (at tip)
- After undo/redo: `seq_cur ~= seq_last` (not at tip)

## Notes

- Independent debounce timers prevent insert/normal mode interference
- Debounce prevents API call spikes during rapid edits
- `TextChanged` covers `:s` substitution commands
