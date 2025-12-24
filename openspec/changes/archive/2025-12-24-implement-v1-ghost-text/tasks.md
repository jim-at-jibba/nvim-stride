# Tasks: Implement V1 Ghost Text

## Phase 1: Foundation
- [x] 1.1 Create `lua/stride/config.lua` with defaults (api_key, endpoint, model, debounce_ms, accept_keymap, context_lines, use_treesitter, disabled_filetypes)
- [x] 1.2 Create `lua/stride/utils.lua` with debounce() and basic get_context()
- [x] 1.3 Write unit tests for config merging
- [x] 1.4 Write unit tests for context extraction (mock buffer)

## Phase 2: Smart Context
- [x] 2.1 Add expand_context_via_treesitter() to utils.lua
- [x] 2.2 Integrate Treesitter expansion into get_context()
- [x] 2.3 Add 50-line expansion cap
- [x] 2.4 Write tests for Treesitter boundary detection

## Phase 3: API Client
- [x] 3.1 Create `lua/stride/client.lua` with fetch_prediction()
- [x] 3.2 Implement plenary.curl POST to Cerebras
- [x] 3.3 Add cursor position tracking for stale check
- [x] 3.4 Add cancel() for in-flight requests
- [x] 3.5 Implement retry logic (3x, exponential backoff)
- [x] 3.6 Add error notifications (401, 429, 5xx)
- [x] 3.7 Write integration tests with mocked HTTP

## Phase 4: Ghost Text UI
- [x] 4.1 Create `lua/stride/ui.lua` with namespace
- [x] 4.2 Implement render() with inline virt_text
- [x] 4.3 Add virt_lines for multi-line completions
- [x] 4.4 Implement clear() to remove extmarks
- [x] 4.5 Track current_suggestion state
- [x] 4.6 Write tests for render/clear cycle

## Phase 5: Core Integration
- [x] 5.1 Rewrite `lua/stride/init.lua` with new architecture
- [x] 5.2 Add setup() with plenary/treesitter checks
- [x] 5.3 Create TextChangedI autocmd with debounce
- [x] 5.4 Add CursorMovedI/InsertLeave/ModeChanged clear handlers
- [x] 5.5 Implement accept() function
- [x] 5.6 Add Tab keymap (expr mode with fallback)
- [x] 5.7 Add is_disabled() filetype check
- [x] 5.8 Delete old `lua/stride/module.lua`
- [x] 5.9 Update plugin/stride.lua if needed
- [x] 5.10 End-to-end manual testing

## Phase 6: Polish
- [x] 6.1 Run `make test` - fix failures
- [x] 6.2 Run `make lint` (stylua) - fix formatting
- [x] 6.3 Update README with setup instructions
- [x] 6.4 Add CEREBRAS_API_KEY documentation

## Dependencies
- Phase 2 depends on Phase 1
- Phase 3 depends on Phase 1
- Phase 4 standalone
- Phase 5 depends on all previous phases
- Phase 6 depends on Phase 5

## Parallelizable
- Phase 3 and Phase 4 can run in parallel after Phase 1
