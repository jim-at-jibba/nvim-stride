# Tasks: Add Treesitter Context Extraction

## Phase 1: Geometry Module

- [x] Create `lua/stride/geo.lua` with Point class
  - [x] `Point.new(row, col)` - Create 1-indexed point
  - [x] `Point.from_cursor()` - Get current cursor position
  - [x] `Point.from_ts(row, col)` - Convert from treesitter (0,0)
  - [x] `Point:to_vim()` - Return (row-1, col-1) for nvim_buf_* APIs
  - [x] `Point:to_ts()` - Return (row-1, col-1) for treesitter
  - [x] `Point:to_cursor()` - Return (row, col-1) for nvim_win_set_cursor
  - [x] `Point:__eq()` - Equality comparison
  - [x] `Point:__lt()` - Less than comparison (for range checks)

- [x] Add Range class to `lua/stride/geo.lua`
  - [x] `Range.new(buf, start_point, end_point)` - Create range
  - [x] `Range.from_ts_node(node, buf)` - Create from treesitter node
  - [x] `Range:contains(point)` - Check if point is within range
  - [x] `Range:to_text()` - Get text within range
  - [x] `Range:replace_text(lines)` - Replace text in range
  - [x] `Range:line_count()` - Number of lines spanned

- [x] Create `tests/stride/geo_spec.lua`
  - [x] Test Point coordinate conversions
  - [x] Test Point comparisons
  - [x] Test Range.from_ts_node
  - [x] Test Range:contains
  - [x] Test Range:to_text
  - [x] Test Range:replace_text

## Phase 2: Treesitter Module

- [x] Create `lua/stride/treesitter.lua`
  - [x] Define FUNCTION_NODES table for supported languages
    - Lua: function_declaration, function_definition
    - JS/TS: function_declaration, arrow_function, method_definition, function_expression
    - Python: function_definition
    - Go: function_declaration, method_declaration
    - Rust: function_item
  - [x] `M.get_containing_function(buf, point)` - Returns {range, text, name} or nil
  - [x] `M.is_supported(filetype)` - Returns boolean
  - [x] `M._get_function_name(node, buf)` - Extract function name from node (internal)

- [x] Create `tests/stride/treesitter_spec.lua`
  - [x] Test get_containing_function with Lua buffer
  - [x] Test get_containing_function returns nil when not in function
  - [x] Test is_supported for known filetypes
  - [x] Test nested function returns innermost

## Phase 3: Context Module

- [x] Create `lua/stride/context.lua`
  - [x] Define Stride.PredictionContext class
    - buf: number
    - cursor: Stride.Point
    - filetype: string
    - file_path: string (relative)
    - containing_function?: {range, text, name}
    - agent_context?: string
  - [x] Static `_agent_cache` table for session-level caching
  - [x] `Context.from_current_buffer()` - Build context from current state
  - [x] `Context:get_function_text()` - Get containing function or nil
  - [x] `Context:get_agent_context()` - Get cached AGENTS.md content or nil
  - [x] `Context:build_prompt_context(start_line, end_line)` - Build numbered lines

- [x] Implement AGENTS.md discovery
  - [x] Walk from file directory up to cwd
  - [x] Check each configured filename
  - [x] Read first match, cache by absolute path
  - [x] Cap content at 2000 chars

- [x] Create `tests/stride/context_spec.lua`
  - [x] Test Context.from_current_buffer
  - [x] Test get_function_text integration
  - [x] Test agent context caching
  - [x] Test build_prompt_context output format

## Phase 4: Config Changes

- [x] Update `lua/stride/config.lua`
  - [x] Add `context_files` option to Stride.Config type
  - [x] Add to defaults: `context_files = false`
  - [x] Document in type annotation

- [ ] Update `tests/stride/stride_spec.lua`
  - [ ] Test context_files defaults to false
  - [ ] Test context_files accepts string array

## Phase 5: Structured Prompt Tags

- [x] Update `lua/stride/predictor.lua` SYSTEM_PROMPT
  - [x] Add XML tag documentation to rules
  - [x] Document <ContainingFunction> tag
  - [x] Document <ProjectRules> tag
  - [x] Document <Cursor> tag
  - [x] Update examples to show tag context

- [x] Create `_build_structured_prompt(ctx, changes_text)` function
  - [x] Build <RecentChanges> tag
  - [x] Build <ContainingFunction> tag (when available)
  - [x] Build <Context> tag with numbered lines
  - [x] Build <ProjectRules> tag (when available)
  - [x] Build <Cursor> tag

## Phase 6: Predictor Refactor

- [x] Update `lua/stride/predictor.lua`
  - [x] Import geo, treesitter, context modules
  - [x] Replace `_get_buffer_context()` usage with Context methods
  - [x] Replace `_get_relative_path()` with Context.file_path
  - [x] Update `fetch_next_edit()` to use PredictionContext
  - [x] Use `_build_structured_prompt()` for user prompt

- [x] Verify all edge cases
  - [x] Treesitter unavailable gracefully falls back
  - [x] No containing function still works
  - [x] No AGENTS.md still works
  - [x] V1 completion mode unaffected

## Phase 7: Utils Cleanup

> **Note**: Skipped - removing `_expand_context_via_treesitter()` and `_is_block_type()` would break V1 mode since `get_context()` depends on them. This contradicts the proposal's risk mitigation: "Keep utils.get_context() unchanged".

- [x] Keep `get_context()` for V1 mode
- [x] Keep `debounce()` and `debounce_normal()`

## Phase 8: Final Validation

- [x] Run full test suite: `make test`
- [ ] Manual testing with Lua file
- [ ] Manual testing with TypeScript file
- [ ] Manual testing with Python file
- [ ] Test with AGENTS.md configured
- [ ] Test without AGENTS.md (default)
- [ ] Verify V1 completion mode still works
- [ ] Update README if needed
