# Design: Add Treesitter Context Extraction

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    predictor.lua                             │
│  fetch_next_edit() → builds prompt → calls LLM              │
├─────────────────────────────────────────────────────────────┤
│                    context.lua                               │
│  PredictionContext: encapsulates all request state          │
│  - from_current_buffer() → builds context                   │
│  - get_function_text() → uses treesitter                    │
│  - get_agent_context() → reads/caches AGENTS.md             │
├──────────────────────┬──────────────────────────────────────┤
│   treesitter.lua     │           geo.lua                    │
│   - Function detect  │   - Point (coordinates)              │
│   - Node walking     │   - Range (spans)                    │
│   - Language support │   - Conversions                      │
└──────────────────────┴──────────────────────────────────────┘
```

## Module Details

### geo.lua

**Purpose**: Centralize coordinate handling to avoid off-by-one bugs.

**Internal representation**: 1-indexed (row, col) matching Lua conventions.

```lua
---@class Stride.Point
---@field row number 1-indexed row
---@field col number 1-indexed column
local Point = {}
Point.__index = Point

-- Conversions handle the index differences:
-- Treesitter: 0-indexed row and col
-- Vim buffer APIs: 0-indexed row and col  
-- Cursor (nvim_win_get/set_cursor): 1-indexed row, 0-indexed col
-- Extmarks: 0-indexed row and col

function Point:to_vim()
  return self.row - 1, self.col - 1
end

function Point:to_ts()
  return self.row - 1, self.col - 1
end

function Point:to_cursor()
  return self.row, self.col - 1
end

function Point.from_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return Point.new(cursor[1], cursor[2] + 1)
end

function Point.from_ts(row, col)
  return Point.new(row + 1, col + 1)
end
```

```lua
---@class Stride.Range
---@field buf number Buffer handle
---@field start Stride.Point Start position (inclusive)
---@field end_ Stride.Point End position (inclusive)
local Range = {}
Range.__index = Range

function Range.from_ts_node(node, buf)
  local sr, sc, er, ec = node:range()
  return Range.new(buf, Point.from_ts(sr, sc), Point.from_ts(er, ec))
end

function Range:contains(point)
  -- Compare using row/col ordering
  local start_val = self.start.row * 1000000 + self.start.col
  local end_val = self.end_.row * 1000000 + self.end_.col
  local point_val = point.row * 1000000 + point.col
  return start_val <= point_val and point_val <= end_val
end

function Range:to_text()
  local sr, sc = self.start:to_vim()
  local er, ec = self.end_:to_vim()
  local lines = vim.api.nvim_buf_get_text(self.buf, sr, sc, er, ec, {})
  return table.concat(lines, "\n")
end
```

### treesitter.lua

**Purpose**: Extract containing function at cursor position.

**Approach**: Node type matching rather than custom query files.

```lua
local FUNCTION_NODES = {
  -- Lua
  ["function_declaration"] = true,
  ["function_definition"] = true,
  -- JavaScript/TypeScript
  ["function_declaration"] = true,
  ["arrow_function"] = true,
  ["method_definition"] = true,
  ["function_expression"] = true,
  -- Python
  ["function_definition"] = true,
  -- Go
  ["function_declaration"] = true,
  ["method_declaration"] = true,
  -- Rust
  ["function_item"] = true,
}

---@class Stride.FunctionInfo
---@field range Stride.Range
---@field text string
---@field name string|nil

---@param buf number
---@param point Stride.Point
---@return Stride.FunctionInfo|nil
function M.get_containing_function(buf, point)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { point:to_ts() },
  })
  
  if not ok or not node then
    return nil
  end
  
  -- Walk up to find function node
  while node do
    if FUNCTION_NODES[node:type()] then
      local range = Range.from_ts_node(node, buf)
      local text = range:to_text()
      local name = M._get_function_name(node, buf)
      return { range = range, text = text, name = name }
    end
    node = node:parent()
  end
  
  return nil
end
```

### context.lua

**Purpose**: Encapsulate all prediction request state.

```lua
---@class Stride.PredictionContext
---@field buf number
---@field cursor Stride.Point
---@field filetype string
---@field file_path string
---@field containing_function? Stride.FunctionInfo
---@field agent_context? string
local Context = {}
Context.__index = Context

-- Session-level cache for AGENTS.md content
local _agent_cache = {}

function Context.from_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = Point.from_cursor()
  local filetype = vim.bo[buf].filetype
  local file_path = -- relative path logic
  
  local ctx = setmetatable({
    buf = buf,
    cursor = cursor,
    filetype = filetype,
    file_path = file_path,
  }, Context)
  
  -- Get containing function if treesitter available
  ctx.containing_function = Treesitter.get_containing_function(buf, cursor)
  
  -- Get agent context if configured
  ctx.agent_context = ctx:_discover_agent_context()
  
  return ctx
end

function Context:_discover_agent_context()
  local Config = require("stride.config")
  local context_files = Config.options.context_files
  
  if not context_files then
    return nil
  end
  
  local cwd = vim.fn.getcwd()
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(self.buf), ":h")
  
  while dir:find(cwd, 1, true) == 1 do
    for _, filename in ipairs(context_files) do
      local path = dir .. "/" .. filename
      
      -- Check cache first
      if _agent_cache[path] then
        return _agent_cache[path]
      end
      
      -- Try to read file
      local file = io.open(path, "r")
      if file then
        local content = file:read("*a")
        file:close()
        -- Cap at 2000 chars
        if #content > 2000 then
          content = content:sub(1, 2000) .. "\n... (truncated)"
        end
        _agent_cache[path] = content
        return content
      end
    end
    
    if dir == cwd then
      break
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  
  return nil
end
```

### Structured Prompt Format

**Current format** (unstructured):
```
Recent changes:
test.lua:5:5
- apple
+ orange

Current context (│ marks cursor position):
test.lua:1:30
1: local function foo()
...

Predict the most likely next edit the user will make.
```

**New format** (structured XML tags):
```xml
<RecentChanges>
test.lua:5:5
- apple
+ orange
</RecentChanges>

<ContainingFunction name="foo" lines="1-15">
local function foo()
  local apple = "fruit"
  print(apple)
end
</ContainingFunction>

<Context file="test.lua" lines="16-45">
16: local function bar()
17:   local config│ = {
18:     value = 1,
19:   }
...
</Context>

<ProjectRules>
Always use snake_case for variables.
Prefer local functions over module functions.
</ProjectRules>

<Cursor line="17" col="14" />
```

**System prompt additions**:
```
- Context is provided in XML tags for clarity
- <RecentChanges> shows the user's recent edits in diff format
- <ContainingFunction> shows the function being edited (when detected)
- <Context> shows numbered lines around cursor with │ marking position
- <ProjectRules> contains project-specific guidelines (when available)
- <Cursor> shows exact cursor position
```

### Config Changes

```lua
---@class Stride.Config
---@field context_files? string[]|false  -- default: false

M.defaults = {
  -- ... existing defaults ...
  context_files = false,  -- e.g., { "AGENTS.md", ".stride.md" }
}
```

## File Structure

```
lua/stride/
├── geo.lua           # NEW: Point/Range geometry
├── treesitter.lua    # NEW: Function extraction
├── context.lua       # NEW: PredictionContext
├── config.lua        # MODIFIED: Add context_files
├── predictor.lua     # MODIFIED: Use Context, structured tags
├── utils.lua         # MODIFIED: Remove treesitter logic
├── init.lua          # unchanged
├── client.lua        # unchanged
├── ui.lua            # unchanged
├── history.lua       # unchanged
└── log.lua           # unchanged

tests/stride/
├── geo_spec.lua      # NEW
├── treesitter_spec.lua # NEW
├── context_spec.lua  # NEW
└── stride_spec.lua   # MODIFIED: Add new tests
```

## Edge Cases

### Treesitter Unavailable

When `vim.treesitter.get_node()` fails or returns nil:
- `containing_function` will be nil
- Prompt built without `<ContainingFunction>` tag
- Falls back to line-based context only

### No AGENTS.md Found

When `context_files` is configured but no file found:
- `agent_context` will be nil
- Prompt built without `<ProjectRules>` tag
- No error, graceful degradation

### Large Functions

Functions exceeding reasonable size (e.g., 100+ lines):
- Could add future option to cap function text
- For now, include full function (LLM handles long context)

### Nested Functions

When cursor is inside nested function:
- Returns innermost containing function
- This is the desired behavior (most specific context)

## Testing Strategy

### Unit Tests

- **geo_spec.lua**: All coordinate conversions, range operations
- **treesitter_spec.lua**: Function detection per language
- **context_spec.lua**: Context building, agent caching

### Integration Tests

- Full prediction flow with new context
- Ensure V1 mode unchanged
- Test with/without treesitter
- Test with/without AGENTS.md

### Manual Testing

1. Open Lua file, edit inside function, verify function context included
2. Open TS file, same test
3. Configure AGENTS.md, verify included in prompt
4. Disable context_files, verify not included
5. V1 completion mode still works
