# LSP Integration for Next-Edit Predictions

This document outlines future enhancements to stride's next-edit prediction system that leverage Neovim's LSP capabilities for more accurate semantic symbol tracking.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [LSP Use Cases](#lsp-use-cases)
3. [Proposed Solution: LSP-First Prediction](#proposed-solution-lsp-first-prediction)
4. [Edit Classification](#edit-classification)
5. [Diagnostic-Driven Suggestions](#diagnostic-driven-suggestions)
6. [Priority Queue & State Machine](#priority-queue--state-machine)
7. [Optional Integrations](#optional-integrations)
8. [Edge Cases & Performance](#edge-cases--performance)
9. [Migration Path](#migration-path)
10. [Testing Strategy](#testing-strategy)

## Problem Statement

Currently, stride uses text-based matching to find occurrences of renamed identifiers. This works well for unique identifiers but struggles with common names:

```typescript
interface User {
  name: string;  // User renames to "firstName"
  email: string;
}

// stride needs to suggest changing user.name below
return <h1>{user.name}</h1>;
```

The issue: `name` appears in many unrelated contexts (`bufname`, class names, etc.). The LLM can't reliably distinguish which `name` references are semantically related to the interface property.

## LSP Use Cases

Beyond rename tracking, LSP integration enables several prediction improvements:

### 1. Rename Propagation (Primary Use Case)

When you rename an identifier, LSP knows all semantic references:

```typescript
// Rename: userName → displayName
const displayName = user.name;

// LSP finds all usages:
console.log(userName);  // → displayName
return <span>{userName}</span>;  // → displayName
```

**API**: `textDocument/references`

### 2. Type-Aware Suggestions

When you change a function's return type or parameter type:

```typescript
// Change return type from string to number
function getCount(): number { ... }  // was: string

// LSP knows these need updating:
const label: string = getCount();  // → const label: number
```

**API**: `textDocument/typeDefinition`, `textDocument/references`

### 3. Signature Change Propagation

When you add/remove/reorder function parameters:

```typescript
// Add required parameter
function createUser(name: string, email: string) { ... }  // added email

// LSP finds all call sites:
createUser("John");  // → needs email arg
createUser(getName());  // → needs email arg
```

**API**: `textDocument/references`, `textDocument/signatureHelp`

### 4. Interface/Type Conformance

When you add a required property to an interface:

```typescript
interface User {
  name: string;
  age: number;  // NEW required field
}

// LSP knows these need updating:
const user: User = { name: "John" };  // missing age
function makeUser(): User { return { name: "x" }; }  // missing age
```

**API**: `textDocument/implementation`, diagnostics

### 5. Import/Export Management

When you rename or move a symbol:

```typescript
// Rename: UserService → AuthService
export class AuthService { ... }

// LSP finds all imports:
import { UserService } from './services';  // → AuthService
```

**API**: `textDocument/references` (includes imports)

### 6. Diagnostic-Driven Predictions

Use LSP errors to predict fixes proactively:

```typescript
// LSP reports: Property 'naem' does not exist on type 'User'
user.naem  // → user.name (typo fix via code action)

// LSP reports: Expected 2 arguments, but got 1
createUser("John")  // → suggest adding missing argument
```

**API**: `textDocument/publishDiagnostics`, `textDocument/codeAction`

### 7. Dead Code Detection

When you delete a function, suggest removing unused imports/calls:

```typescript
// Deleted: function unusedHelper() { ... }

// LSP can identify via diagnostics:
import { unusedHelper } from './utils';  // → remove unused import
```

**API**: Diagnostics for unused variables/imports

### Summary Table

| Use Case | LSP API | Benefit |
|----------|---------|---------|
| Rename propagation | `references` | Semantic accuracy |
| Type changes | `typeDefinition` + `references` | Update type annotations |
| Signature changes | `references` + `signatureHelp` | Parameter updates at call sites |
| Interface compliance | `implementation` + diagnostics | Find implementers |
| Import fixes | `references` | Cross-file awareness |
| Error-driven fixes | `diagnostics` + `codeAction` | Proactive fixes |
| Dead code removal | diagnostics | Clean up unused code |

## Proposed Solution: LSP-First Prediction

Use Neovim's LSP `textDocument/references` to get semantic symbol locations before falling back to LLM-based prediction.

### Enhanced Architecture

```
User edits → InsertLeave
                │
                ▼
        ┌───────────────────┐
        │ Classify edit     │
        │ (rename/sig/type) │
        └───────────────────┘
                │
    ┌───────────┼───────────┬────────────────┐
    ▼           ▼           ▼                ▼
 Rename?    Signature?   Type change?    Has diagnostic?
    │           │           │                │
    ▼           ▼           ▼                ▼
LSP refs    LSP refs +   LSP refs      LSP codeAction
            signatureHelp
    │           │           │                │
    └───────────┴───────────┴────────────────┘
                │
                ▼
        ┌───────────────────┐
        │ Build edit queue  │
        │ (prioritized)     │
        └───────────────────┘
                │
                ▼
        ┌───────────────────┐
        │ Show first [1/N]  │
        │ Tab cycles        │
        └───────────────────┘
                │
                ▼ (queue empty)
        ┌───────────────────┐
        │ Fall back to LLM  │
        │ for other edits   │
        └───────────────────┘
```

### Simple Architecture (Rename Only)

```
┌─────────────────────────────────────────────────────────────┐
│                    InsertLeave triggered                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Detect edit type from History                           │
│     - Is this a rename? (identifier changed)                │
│     - Is cursor on an identifier?                           │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │ LSP available + rename-like?  │
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────┐
│  2a. Query LSP refs     │     │  2b. Use existing LLM flow  │
│  at original position   │     │      (no change)            │
└─────────────────────────┘     └─────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Find refs still containing OLD value                    │
│     (haven't been renamed yet)                              │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Store ALL pending edits, show first with count          │
│     e.g., "user.name → firstName [1/3]"                     │
└─────────────────────────────────────────────────────────────┘
```

### Benefits

| Aspect | Current (LLM) | Proposed (LSP-first) |
|--------|---------------|----------------------|
| Accuracy | Text matching, prone to false positives | Semantic, understands scope/types |
| Latency | ~200-500ms per LLM call | ~50ms for LSP refs |
| Count | Unknown (incremental discovery) | Known upfront |
| Cost | LLM API call per edit | No API cost for renames |

### Neovim LSP APIs

#### Get References

```lua
local function get_references(buf, pos, callback)
  local params = vim.lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  
  vim.lsp.buf_request_all(buf, 'textDocument/references', params, function(results)
    local locations = {}
    for _, client_result in pairs(results) do
      if client_result.result then
        vim.list_extend(locations, client_result.result)
      end
    end
    callback(locations)
  end)
end
```

#### Check LSP Availability

```lua
local function has_reference_support(buf)
  local clients = vim.lsp.get_clients({ bufnr = buf })
  for _, client in ipairs(clients) do
    if client.server_capabilities.referencesProvider then
      return true
    end
  end
  return false
end
```

### Implementation Outline

#### New Module: `lua/stride/lsp.lua`

```lua
local M = {}

---Check if LSP reference support is available
---@param buf number
---@return boolean
function M.has_reference_support(buf)
  local clients = vim.lsp.get_clients({ bufnr = buf })
  for _, client in ipairs(clients) do
    if client.server_capabilities.referencesProvider then
      return true
    end
  end
  return false
end

---Get semantic references for symbol at position
---@param buf number Buffer handle
---@param pos {line: number, col: number} 1-indexed line, 0-indexed col
---@param timeout_ms number Max time to wait
---@param callback fun(locations: table[]|nil)
function M.get_references(buf, pos, timeout_ms, callback)
  -- Implementation using vim.lsp.buf_request_all
end

return M
```

#### Config Changes

```lua
M.defaults = {
  -- ... existing options ...
  use_lsp = true,           -- Enable LSP-enhanced predictions
  lsp_timeout_ms = 500,     -- Max wait for LSP refs
}
```

#### Predictor Changes

```lua
---@class Stride.PendingEdits
---@field suggestions Stride.RemoteSuggestion[]
---@field current_index number
---@field total number

M._pending_edits = nil

function M.fetch_next_edit(buf, cursor_pos, callback)
  local recent_change = History.get_most_recent()
  
  -- Try LSP path for identifier renames
  if Config.options.use_lsp 
     and Lsp.has_reference_support(buf) 
     and _is_identifier_rename(recent_change) then
    
    Lsp.get_references(buf, recent_change.pos, Config.options.lsp_timeout_ms, function(refs)
      if not refs then
        -- LSP failed/timed out, fall back to LLM
        M._fetch_from_llm(buf, cursor_pos, callback)
        return
      end
      
      local stale_refs = _filter_stale_refs(refs, recent_change.old_text, buf)
      if #stale_refs == 0 then
        -- No stale refs, might be complete or fall back to LLM
        callback(nil, 0)
        return
      end
      
      -- Store all pending edits
      M._pending_edits = {
        suggestions = _create_suggestions(stale_refs, recent_change),
        current_index = 1,
        total = #stale_refs,
      }
      
      -- Return first + total count
      callback(M._pending_edits.suggestions[1], M._pending_edits.total)
    end)
  else
    M._fetch_from_llm(buf, cursor_pos, callback)
  end
end

---Advance to next pending edit (called after Tab accept)
---@return Stride.RemoteSuggestion|nil, number remaining
function M.advance_to_next()
  if not M._pending_edits then
    return nil, 0
  end
  
  local pe = M._pending_edits
  if pe.current_index >= pe.total then
    M._pending_edits = nil
    return nil, 0
  end
  
  pe.current_index = pe.current_index + 1
  local remaining = pe.total - pe.current_index + 1
  return pe.suggestions[pe.current_index], remaining
end

---Clear pending edits (on cursor move, mode change, etc.)
function M.clear_pending()
  M._pending_edits = nil
end
```

#### UI Changes

```lua
---Render a remote suggestion with optional count indicator
---@param suggestion Stride.RemoteSuggestion
---@param buf number
---@param current number|nil Current index (1-based)
---@param total number|nil Total pending edits
function M.render_remote(suggestion, buf, current, total)
  -- ... existing rendering code ...
  
  -- Add count indicator if multiple edits
  local suffix = ""
  if total and total > 1 then
    suffix = string.format(" [%d/%d]", current or 1, total)
  end
  
  local ok_virt, virt_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, suggestion.col_end, {
    virt_text = { { " → " .. suggestion.new .. suffix, "StrideRemoteSuggestion" } },
    virt_text_pos = "inline",
  })
  
  -- ... rest of rendering ...
end
```

## Edit Classification

To route edits to the appropriate LSP query, we need to classify what kind of edit occurred.

### Edit Classifier Module

```lua
---@class Stride.EditType
---@field kind "rename"|"signature"|"type"|"delete"|"unknown"
---@field old_value string
---@field new_value string
---@field position {line: number, col: number}
---@field node_type? string Treesitter node type

---Classify the most recent edit using treesitter
---@param buf number
---@param change Stride.TrackedChange
---@return Stride.EditType
local function classify_edit(buf, change)
  local pos = change.range
  
  -- Get treesitter node at edit position
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { pos.start_line - 1, pos.start_col },
  })
  
  if not ok or not node then
    return { kind = "unknown", old_value = change.old_text, new_value = change.new_text, position = pos }
  end
  
  local node_type = node:type()
  
  -- Classify based on node type (language-dependent)
  local classification = {
    -- Identifiers → likely rename
    identifier = "rename",
    property_identifier = "rename",
    type_identifier = "rename",
    
    -- Parameter lists → signature change
    formal_parameters = "signature",
    parameter_list = "signature",
    required_parameter = "signature",
    
    -- Type annotations → type change
    type_annotation = "type",
    predefined_type = "type",
  }
  
  return {
    kind = classification[node_type] or "unknown",
    old_value = change.old_text,
    new_value = change.new_text,
    position = { line = pos.start_line, col = pos.start_col },
    node_type = node_type,
  }
end
```

### LSP Query Router

Based on edit type, query appropriate LSP endpoints:

```lua
---@type table<string, fun(buf: number, pos: table, callback: function)>
local query_strategies = {
  rename = function(buf, pos, callback)
    -- textDocument/references for the symbol
    Lsp.get_references(buf, pos, function(refs)
      callback(refs)
    end)
  end,
  
  signature = function(buf, pos, callback)
    -- Get refs to the function, filter to call sites
    Lsp.get_references(buf, pos, function(refs)
      local call_sites = filter_call_sites(refs, buf)
      callback(call_sites)
    end)
  end,
  
  type = function(buf, pos, callback)
    -- Get refs to the typed variable/function
    Lsp.get_references(buf, pos, callback)
  end,
  
  unknown = function(buf, pos, callback)
    -- Fall back to LLM
    callback(nil)
  end,
}
```

## Diagnostic-Driven Suggestions

LSP diagnostics can drive proactive fix suggestions, especially useful after edits that introduce errors.

### Getting Actionable Diagnostics

```lua
---Get code actions for diagnostics near cursor
---@param buf number
---@param pos {line: number, col: number}
---@param callback fun(actions: table[])
local function get_diagnostic_actions(buf, pos, callback)
  -- Get diagnostics on or near the cursor line
  local diagnostics = vim.diagnostic.get(buf, {
    lnum = pos.line - 1,
    severity = { min = vim.diagnostic.severity.WARN },
  })
  
  if #diagnostics == 0 then
    callback({})
    return
  end
  
  -- Request code actions for these diagnostics
  local params = vim.lsp.util.make_range_params()
  params.context = {
    diagnostics = diagnostics,
    only = { "quickfix" },  -- Only quick fixes, not refactors
  }
  
  vim.lsp.buf_request_all(buf, 'textDocument/codeAction', params, function(results)
    local actions = {}
    for _, client_result in pairs(results) do
      if client_result.result then
        vim.list_extend(actions, client_result.result)
      end
    end
    callback(actions)
  end)
end
```

### Converting Code Actions to Suggestions

```lua
---Convert LSP code action to stride suggestion
---@param action table LSP CodeAction
---@param buf number
---@return Stride.RemoteSuggestion|nil
local function code_action_to_suggestion(action, buf)
  -- Code actions can have either edit or command
  if not action.edit then
    return nil  -- Command-only actions not supported yet
  end
  
  local changes = action.edit.changes or {}
  
  -- For now, only handle single-file, single-edit actions
  for uri, edits in pairs(changes) do
    if uri == vim.uri_from_bufnr(buf) and #edits == 1 then
      local edit = edits[1]
      local range = edit.range
      return {
        line = range.start.line + 1,
        col_start = range.start.character,
        col_end = range["end"].character,
        original = get_text_in_range(buf, range),
        new = edit.newText,
        is_remote = true,
        source = "diagnostic",
      }
    end
  end
  
  return nil
end
```

### UI for Diagnostic Suggestions

```
// Error: Property 'naem' does not exist on type 'User'
user.naem  →  user.name [quickfix]
      ~~~~
```

## Priority Queue & State Machine

When multiple suggestion sources are available, we need to prioritize and manage state.

### Unified Suggestion Type

```lua
---@class Stride.Suggestion
---@field kind "rename"|"signature"|"type"|"diagnostic"|"llm"
---@field line number 1-indexed
---@field col_start number 0-indexed
---@field col_end number 0-indexed
---@field original string
---@field new string
---@field source "lsp"|"llm"
---@field confidence number 0-1 (LSP = 1.0, LLM varies)
---@field is_remote boolean
```

### Priority Order

```lua
local PRIORITY = {
  diagnostic = 1,   -- Errors first (blocking issues)
  rename = 2,       -- Direct symbol references
  signature = 3,    -- Call site parameter updates
  type = 4,         -- Type annotation updates
  llm = 5,          -- LLM predictions (fallback)
}

---Sort suggestions by priority
---@param suggestions Stride.Suggestion[]
---@return Stride.Suggestion[]
local function sort_by_priority(suggestions)
  table.sort(suggestions, function(a, b)
    local pa = PRIORITY[a.kind] or 99
    local pb = PRIORITY[b.kind] or 99
    if pa ~= pb then
      return pa < pb
    end
    -- Within same priority, sort by line number (closest first)
    return a.line < b.line
  end)
  return suggestions
end
```

### State Machine

```
┌─────────┐    edit    ┌──────────┐   LSP/LLM   ┌───────────┐
│  IDLE   │ ─────────► │ ANALYZE  │ ──────────► │  PENDING  │
└─────────┘            └──────────┘             └───────────┘
     ▲                                                │
     │                                                │ Tab
     │  cursor move                                   ▼
     │  / new edit   ┌──────────┐             ┌───────────┐
     └────────────── │  EMPTY   │ ◄────────── │  CYCLING  │
                     └──────────┘   queue     └───────────┘
                          │         empty           │
                          │                         │ Tab
                          ▼                         │
                    ┌──────────┐                    │
                    │ RE-QUERY │◄───────────────────┘
                    │   LLM    │   (for non-LSP edits)
                    └──────────┘
```

### Pending Edits Manager

```lua
---@class Stride.EditQueue
---@field suggestions Stride.Suggestion[]
---@field current_index number
---@field total number

local M = {}
M._queue = nil

---Initialize queue with suggestions
---@param suggestions Stride.Suggestion[]
function M.init_queue(suggestions)
  if #suggestions == 0 then
    M._queue = nil
    return
  end
  
  M._queue = {
    suggestions = sort_by_priority(suggestions),
    current_index = 1,
    total = #suggestions,
  }
end

---Get current suggestion
---@return Stride.Suggestion|nil, number current, number total
function M.current()
  if not M._queue then
    return nil, 0, 0
  end
  return M._queue.suggestions[M._queue.current_index],
         M._queue.current_index,
         M._queue.total
end

---Advance to next suggestion
---@return Stride.Suggestion|nil, number current, number total
function M.advance()
  if not M._queue then
    return nil, 0, 0
  end
  
  if M._queue.current_index >= M._queue.total then
    M._queue = nil
    return nil, 0, 0
  end
  
  M._queue.current_index = M._queue.current_index + 1
  return M.current()
end

---Clear queue (on cursor move, new edit, etc.)
function M.clear()
  M._queue = nil
end

---Check if queue has items
---@return boolean
function M.has_pending()
  return M._queue ~= nil and M._queue.current_index <= M._queue.total
end
```

### Tab Handler Integration

```lua
function M.accept()
  local suggestion, current, total = EditQueue.current()
  if not suggestion then
    return "<Tab>"
  end
  
  -- Apply the edit
  apply_suggestion(suggestion)
  
  -- Advance to next
  local next_suggestion, next_current, next_total = EditQueue.advance()
  
  if next_suggestion then
    -- Show next suggestion with updated count
    Ui.render_remote(next_suggestion, buf, next_current, next_total)
  else
    -- Queue exhausted
    if should_requery_llm() then
      -- Trigger LLM for additional predictions
      trigger_llm_prediction()
    end
  end
  
  return ""
end
```

## Optional Integrations

### Fidget.nvim Integration

For users with [fidget.nvim](https://github.com/j-hui/fidget.nvim) installed, show a notification when multiple edits are detected:

```lua
local function notify_pending_edits(count, kind)
  local ok, fidget = pcall(require, "fidget")
  if ok then
    local msg = kind == "diagnostic" 
      and string.format("%d fixes available", count)
      or string.format("%d edits detected", count)
    
    fidget.notify(msg, vim.log.levels.INFO, {
      annote = "Tab to apply",
      key = "stride-edits",
      ttl = 5,
    })
  end
end

-- Update notification as user cycles through
local function update_pending_notification(current, total)
  local ok, fidget = pcall(require, "fidget")
  if ok and total > 1 then
    fidget.notify(
      string.format("Edit %d/%d", current, total),
      vim.log.levels.INFO,
      { key = "stride-edits", ttl = 3 }
    )
  end
end
```

### Lualine Integration

Expose a statusline component showing pending edit count:

```lua
-- In stride module
function M.statusline()
  local suggestion, current, total = EditQueue.current()
  if not suggestion then
    return ""
  end
  return string.format("󰏫 %d/%d", current, total)
end

-- User's lualine config
require('lualine').setup({
  sections = {
    lualine_x = {
      { require('stride').statusline },
    },
  },
})
```

### Which-Key Integration

Show pending edits in which-key popup:

```lua
-- Register Tab mapping with dynamic description
vim.keymap.set("n", "<Tab>", function()
  local _, current, total = require("stride").get_pending()
  if total > 0 then
    return require("stride").accept()
  end
  return "<Tab>"
end, {
  expr = true,
  desc = function()
    local _, current, total = require("stride").get_pending()
    if total > 0 then
      return string.format("Accept edit [%d/%d]", current, total)
    end
    return "Tab"
  end,
})
```

## Edge Cases & Performance

### Detecting Rename-Like Edits

```lua
---Check if a change looks like an identifier rename
---@param change Stride.TrackedChange
---@return boolean
local function _is_identifier_rename(change)
  if not change then return false end
  
  local old = change.old_text
  local new = change.new_text
  
  -- Both must be valid identifiers (alphanumeric + underscore, not starting with digit)
  local identifier_pattern = "^[%a_][%w_]*$"
  
  return old:match(identifier_pattern) ~= nil 
     and new:match(identifier_pattern) ~= nil
     and old ~= new
end
```

### Edge Cases

| Case | Handling |
|------|----------|
| No LSP attached | Fall back to LLM path |
| LSP timeout | Fall back to LLM path after `lsp_timeout_ms` |
| No references found | Return nil (edit complete) |
| All refs already updated | Return nil (edit complete) |
| User moves cursor | Clear pending edits |
| User makes new edit | Clear pending, start fresh |
| Diagnostic has no code action | Skip, try next suggestion |
| Code action is command-only | Skip (not supported yet) |

### History Module Changes

Track the original position of edits for LSP lookups:

```lua
---@class Stride.TrackedChange
---@field file string
---@field old_text string
---@field new_text string
---@field range {start_line: number, start_col: number, end_line: number, end_col: number}
---@field timestamp number
---@field cursor_pos? {line: number, col: number}  -- NEW: position for LSP lookup
```

### Cross-File References (Future)

LSP returns references across all files in the workspace. Future enhancement could:

1. Group refs by file
2. Show current-file refs first
3. Offer to jump to other files
4. Show notification: "3 edits in this file, 5 in other files"

For now, filter to current buffer only:

```lua
local function filter_to_current_buffer(refs, buf)
  local buf_uri = vim.uri_from_bufnr(buf)
  return vim.tbl_filter(function(ref)
    return ref.uri == buf_uri
  end, refs)
end
```

### Treesitter Fallback

For when LSP is unavailable, treesitter could provide partial semantic understanding:

```lua
-- Find property accesses on a variable
local query = vim.treesitter.query.parse('typescript', [[
  (member_expression
    object: (identifier) @obj
    property: (property_identifier) @prop)
]])
```

Limitations:
- No cross-file support
- No type information
- Language-specific queries needed

### Performance Considerations

| Operation | Expected Latency |
|-----------|-----------------|
| LSP references | 20-100ms |
| LSP code actions | 30-150ms |
| LLM API call | 200-500ms |
| Edit classification | <5ms |
| Filter stale refs | <1ms |
| Render UI | <1ms |

LSP path is 4-10x faster for rename cases.

## Migration Path

### Phase 1: LSP References for Renames
1. Implement `lua/stride/lsp.lua` with reference support
2. Add config options (`use_lsp`, `lsp_timeout_ms`)
3. Integrate into predictor with feature flag
4. Add count indicator `[1/N]` to UI
5. Add optional fidget integration

### Phase 2: Edit Classification
1. Add treesitter-based edit classifier
2. Route different edit types to appropriate LSP queries
3. Support signature and type change detection

### Phase 3: Diagnostic Integration
1. Query diagnostics after edits
2. Convert code actions to suggestions
3. Prioritize diagnostic fixes in queue

### Phase 4: Cross-File Support
1. Group references by file
2. Add UI for cross-file navigation
3. Support jumping to other files for edits

## Testing Strategy

1. **Unit tests**: Mock LSP responses, verify suggestion creation
2. **Integration tests**: Use real TypeScript/Lua LSP in test buffer
3. **Demo files**: Add demo scenarios that specifically test:
   - Interface property rename
   - Variable rename with multiple usages
   - Function parameter rename  
   - Signature changes
   - Diagnostic-driven fixes
   - Cases where LSP should fall back to LLM
