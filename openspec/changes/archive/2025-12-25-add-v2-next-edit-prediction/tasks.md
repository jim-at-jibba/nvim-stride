## 1. History Module

- [x] 1.1 Create `lua/stride/history.lua` scaffold with module pattern
- [x] 1.2 Define `Stride.EditDiff` class (change_type, line, original, new)
- [x] 1.3 Implement `take_snapshot(buf)` - store buffer lines on InsertEnter
- [x] 1.4 Implement `compute_diff(buf)` - compare snapshot vs current using `vim.diff()`
- [x] 1.5 Parse unified diff output into structured `EditDiff[]` objects
- [x] 1.6 Add debug logging for snapshot/diff operations
- [x] 1.7 Write unit tests for diff parsing edge cases

## 2. Predictor Module

- [x] 2.1 Create `lua/stride/predictor.lua` scaffold
- [x] 2.2 Define `Stride.RemoteSuggestion` class (line, original, new, col_start, col_end)
- [x] 2.3 Design prompt template with RECENT_EDIT + FILE_CONTEXT + TASK sections
- [x] 2.4 Implement `fetch_next_edit(diffs, context, callback)` using curl
- [x] 2.5 Implement JSON response parsing with strict validation
- [x] 2.6 Validate target line exists and original text matches
- [x] 2.7 Add debug logging for request/response cycle
- [ ] 2.8 Write unit tests for JSON parsing and validation

## 3. Remote UI

- [x] 3.1 Define `StrideReplace` highlight group (red/strikethrough)
- [x] 3.2 Define `StrideRemoteSuggestion` highlight group (cyan)
- [x] 3.3 Add `is_remote` and `target_line` fields to `Stride.Suggestion`
- [x] 3.4 Implement `render_remote(suggestion)` in ui.lua
- [x] 3.5 Highlight original text on target line
- [x] 3.6 Add EOL virtual text showing replacement
- [x] 3.7 Update `clear()` to handle remote extmarks
- [x] 3.8 Write tests for remote rendering

## 4. Jump & Accept

- [x] 4.1 Modify `accept()` to check `suggestion.is_remote`
- [x] 4.2 Implement cursor jump to target line
- [x] 4.3 Apply text replacement at remote location
- [x] 4.4 Clear suggestion after acceptance
- [x] 4.5 Auto-trigger next prediction after accepting remote edit
- [ ] 4.6 Test jump-and-apply flow end-to-end (manual)

## 5. Autocmd Integration

- [x] 5.1 Add `InsertEnter` autocmd calling `history.take_snapshot()`
- [x] 5.2 Modify `TextChangedI` handler to compute diff when mode includes refactor
- [x] 5.3 Call `predictor.fetch_next_edit()` after diff computation
- [x] 5.4 Wire up remote UI rendering on predictor callback
- [x] 5.5 Ensure V1 completion still works alongside V2

## 6. Configuration

- [x] 6.1 Add `mode` option: "completion" | "refactor" | "both"
- [x] 6.2 Add `show_remote` option (default: true)
- [x] 6.3 Update config type annotations
- [x] 6.4 Update defaults (mode = "completion" for backward compat)
- [x] 6.5 Write config validation tests

## 7. Documentation & Polish

- [ ] 7.1 Update README with V2 features
- [ ] 7.2 Add V2 usage examples
- [ ] 7.3 Document new config options
- [x] 7.4 Run full test suite (20 tests passing)
- [ ] 7.5 Manual testing of tab-tab-tab flow
