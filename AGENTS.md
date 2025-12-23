# AGENTS.md

Guide for AI agents working on this Neovim plugin. Based on patterns from [flash.nvim](https://github.com/folke/flash.nvim).

## Architecture

### Directory Structure

```
lua/
  plugin_name/        # Internal modules
    module.lua        # Feature modules
  plugin_name.lua     # Main entry point, public API, setup()
plugin/
  plugin_name.lua     # Vim commands, autocommands
tests/
  plugin_name/        # Test files per module
  minimal_init.lua    # Test harness
doc/                  # Help documentation
```

### Layered Design

```
┌─────────────────────────────────┐
│  Public API (plugin_name.lua)   │  User-facing: setup(), commands
├─────────────────────────────────┤
│  Plugins/Modes                  │  Feature implementations
├─────────────────────────────────┤
│  Core Modules                   │  Business logic
├─────────────────────────────────┤
│  Utilities                      │  Helpers, low-level
└─────────────────────────────────┘
```

### Module Pattern

```lua
-- Every module follows this structure
local M = {}
M.__index = M  -- If class-like

-- Private state
local state = {}

-- Private functions (local)
local function helper() end

-- Public methods
function M.new() end
function M:method() end

return M
```

## Style Guide

### Naming

| Type | Convention | Example |
|------|------------|---------|
| Functions | snake_case | `get_matches`, `update_state` |
| Private funcs | underscore prefix | `M:_update()`, `M:_call()` |
| Variables | snake_case | `match_count`, `win_id` |
| Constants | UPPER_CASE | `M.ESC`, `M.CR` |
| Module table | `M` | `local M = {}` |
| Requires | PascalCase | `local Config = require(...)` |

### Type Annotations (LuaLS/EmmyLua)

Required on all public functions and classes:

```lua
---@class Flash.Match
---@field win number
---@field pos Pos
---@field label? string|false

---@param opts? Config
---@return Match[]
function M.find(opts) end

-- Inline for fields
mode = "exact", ---@type "exact"|"fuzzy"|"regex"
```

### Error Handling

```lua
-- pcall for external calls
local ok, ret = pcall(vim.fn.getcharstr)
if not ok then return nil end

-- Graceful degradation with user notification
local ok, parser = pcall(vim.treesitter.get_parser, buf)
if not ok then
  vim.notify("No parser", vim.log.levels.WARN, { title = "plugin_name" })
  return {}
end
```

### Configuration Pattern

```lua
local defaults = {
  opt = "default",
  nested = {
    enabled = true,
  },
}

---@param opts? Config
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
end
```

### Formatting

- Formatter: stylua
- Indent: 2 spaces
- Line width: 120
- Quotes: double preferred
- Line endings: Unix

## Testing

### Framework

busted via minimal_init.lua

### Patterns

```lua
describe("feature", function()
  before_each(function()
    -- Reset state
  end)

  it("does thing", function()
    assert.same(expected, actual)
  end)
end)
```

### Data-driven tests

```lua
local tests = {
  { input = "a", expected = "b" },
  { input = "c", expected = "d" },
}

for _, t in ipairs(tests) do
  it("handles " .. t.input, function()
    assert.same(t.expected, fn(t.input))
  end)
end
```

### Run tests

```bash
make test
```

## Key Patterns

### 1. Facade for Public API

```lua
-- init.lua exposes clean API, delegates to internal modules
local M = {}

function M.setup(opts)
  require("plugin_name.config").setup(opts)
end

return setmetatable(M, {
  __index = function(_, k)
    return require("plugin_name.commands")[k]
  end,
})
```

### 2. Lazy Module Loading

```lua
local mod = nil
local function load()
  if not mod then mod = require("plugin_name.heavy") end
  return mod
end
```

### 3. Extensibility via Callbacks

```lua
-- Allow users to customize behavior
M.find({
  matcher = function(win, state)
    return custom_matches
  end,
  filter = function(matches)
    return filtered
  end,
})
```

### 4. State Machine for Sessions

```lua
function M:loop()
  while self.visible do
    self:update()
    local char = self:get_char()
    if not char then break end
    self:step(char)
  end
end
```

### 5. Mode Inheritance

```lua
modes = {
  search = { ... },
  char = { mode = "search", ... },  -- inherits from search
}
```

## Git/GitHub

- Use GitHub CLI (`gh`) for PR/issue operations
- Commits: concise, imperative mood
- Run `make lint` before committing

## Common Tasks

### Add new feature module

1. Create `lua/plugin_name/feature.lua`
2. Add type annotations
3. Export from main module if public
4. Add tests in `tests/plugin_name/feature_spec.lua`

### Add configuration option

1. Add to defaults in config module
2. Add `---@field` annotation
3. Document in README

### Add user command

```lua
-- plugin/plugin_name.lua
vim.api.nvim_create_user_command("CmdName", function(opts)
  require("plugin_name").feature(opts.args)
end, { nargs = "?" })
```
